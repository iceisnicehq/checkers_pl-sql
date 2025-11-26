CREATE OR REPLACE PACKAGE BODY C##CHECKERS_APP.game_logic AS

    -- =========================================================================
    -- КОНСТАНТЫ
    -- =========================================================================
    c_white_man     CONSTANT VARCHAR2(1) := 'w';
    c_black_man     CONSTANT VARCHAR2(1) := 'b';
    c_white_king    CONSTANT VARCHAR2(1) := 'W';
    c_black_king    CONSTANT VARCHAR2(1) := 'B';
    c_empty_field   CONSTANT VARCHAR2(1) := '+';

    -- =========================================================================
    -- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ И ТИПЫ ДЛЯ ВНУТРЕННЕГО ИСПОЛЬЗОВАНИЯ
    -- =========================================================================
    TYPE rec_board_field IS RECORD(
        idx      PLS_INTEGER,
        notation VARCHAR2(10), -- Увеличено с 2 до 10 для поддержки нотаций типа 'j10' для досок 10x10
        row_num  PLS_INTEGER,
        col_num  PLS_INTEGER
    );
    -- Тип для карты "нотация -> поле"
    TYPE map_notation_to_field IS TABLE OF rec_board_field INDEX BY VARCHAR2(10); -- Увеличено до 10 (для 'j10')
    
    -- Тип для карты "индекс -> поле"
    TYPE map_idx_to_field IS TABLE OF rec_board_field INDEX BY PLS_INTEGER;

    -- Наши глобальные переменные-кэши
    g_map_by_notation   map_notation_to_field;
    g_map_by_idx        map_idx_to_field;
    
    -- "Флаг" который говорит нам, карта какого размера сейчас в кэше
    g_current_map_size  PLS_INTEGER := 0;

-- @function encode_board
-- @brief Compresses (encodes) a board string using RLE.
-- [ИЗМЕНЕНИЕ] Увеличен буфер v_encoded_board для поддержки 10x10 без риска переполнения
FUNCTION encode_board(p_decoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_encoded_board VARCHAR2(128) := '';
    v_plus_count    PLS_INTEGER := 0;
    v_char          CHAR(1);
BEGIN
    -- Если строка не содержит плюсов, возможно, она уже сжата.
    IF INSTR(p_decoded_board, c_empty_field) = 0 THEN
        RETURN p_decoded_board;
    END IF;

    FOR i IN 1 .. LENGTH(p_decoded_board) LOOP
        v_char := SUBSTR(p_decoded_board, i, 1);
        IF v_char = c_empty_field THEN
            v_plus_count := v_plus_count + 1;
        ELSE
            IF v_plus_count > 0 THEN
                v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
                v_plus_count := 0;
            END IF;
            v_encoded_board := v_encoded_board || v_char;
        END IF;
    END LOOP;

    IF v_plus_count > 0 THEN
        v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
    END IF;

    RETURN v_encoded_board;
END encode_board;
-- @function decode_board
-- @brief Decompresses (decodes) an RLE board string into a full string.
-- [ИЗМЕНЕНИЕ] Увеличен буфер v_decoded_board для поддержки 10x10
FUNCTION decode_board(p_encoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_decoded_board VARCHAR2(128) := ''; 
    v_num_str       VARCHAR2(2) := '';
    v_char          CHAR(1);
    i               PLS_INTEGER := 1;
BEGIN
    -- Если строка содержит плюсы, она уже, скорее всего, раскодирована.
    IF INSTR(p_encoded_board, c_empty_field) > 0 THEN
        RETURN p_encoded_board;
    END IF;

    WHILE i <= LENGTH(p_encoded_board) LOOP
        v_char := SUBSTR(p_encoded_board, i, 1);

        IF v_char BETWEEN '0' AND '9' THEN
            v_num_str := v_num_str || v_char;
        ELSE
            IF v_num_str IS NOT NULL THEN
                v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
                v_num_str := '';
            END IF;
            v_decoded_board := v_decoded_board || v_char;
        END IF;
        i := i + 1;
    END LOOP;

    IF v_num_str IS NOT NULL THEN
        v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
    END IF;

    RETURN v_decoded_board;
END decode_board;
-- @function get_active_game
-- @brief Finds ANY active session (game OR spectating).
-- @return game_id if the player is busy (playing or watching), otherwise NULL.
-- @dependencies:
--   - games (table)
--   - spectators (table)

FUNCTION get_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
    v_game_id games.game_id%TYPE;
BEGIN
    -- 1. Сначала ищем, не ИГРАЕТ ли пользователь
    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM games
        WHERE (player_white_id = p_user_id OR player_black_id = p_user_id)
          AND status IN ('A', 'O', 'C'); -- Активна, Открыта, Вызов
        
        -- Если нашли, он занят. Возвращаем ID.
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL; -- Не играет. Проверяем, не смотрит ли он.
    END;

    -- 2. Если не играет, ищем, не СМОТРИТ ли он
    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM spectators
        WHERE player_id = p_user_id
          AND left_at IS NULL
          AND ROWNUM = 1;
        
        -- Если нашли, он тоже занят.
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Не играет и не смотрит. Он свободен.
            RETURN NULL;
    END;
END get_active_game;
-- @function get_or_create_player_id
-- @brief Retrieves the player_id for a given username, creating the player if it doesn't exist.
-- @dependencies:
--   - players (table)

FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
    v_player_id players.player_id%TYPE;
    v_current_season_id seasons.season_id%TYPE;
BEGIN
    BEGIN
        SELECT player_id
        INTO v_player_id
        FROM players
        WHERE username = p_username;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO players (username)
            VALUES (p_username)
            RETURNING player_id INTO v_player_id;
            
            -- Создаем начальные рейтинги для нового игрока (500 по умолчанию)
            -- Для всех правил и текущего сезона
            BEGIN
                -- Получаем текущий сезон
                SELECT season_id INTO v_current_season_id
                FROM seasons
                WHERE SYSDATE BETWEEN start_date AND end_date
                AND ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Если сезона нет, берем последний созданный или создаем новый
                    BEGIN
                        SELECT MAX(season_id) INTO v_current_season_id FROM seasons;
                        IF v_current_season_id IS NULL THEN
                            -- Создаем сезон если его нет
                            DECLARE
                                v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                                    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                                    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
                                );
                                v_month_num PLS_INTEGER := EXTRACT(MONTH FROM SYSDATE);
                                v_year_num PLS_INTEGER := EXTRACT(YEAR FROM SYSDATE);
                                v_season_name VARCHAR2(100) := v_month_names(v_month_num) || '-' || v_year_num;
                                v_start_date DATE := TRUNC(SYSDATE, 'MM');
                                v_end_date DATE := ADD_MONTHS(v_start_date, 1) - 1;
                            BEGIN
                                INSERT INTO seasons (season_name, start_date, end_date)
                                VALUES (v_season_name, v_start_date, v_end_date)
                                RETURNING season_id INTO v_current_season_id;
                            END;
                        END IF;
                    END;
            END;
            
            -- Создаем рейтинги для всех правил
            IF v_current_season_id IS NOT NULL THEN
                FOR r IN (SELECT rule_id FROM game_rules) LOOP
                    BEGIN
                        INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                        VALUES (v_player_id, r.rule_id, v_current_season_id, 500);
                    EXCEPTION
                        WHEN OTHERS THEN NULL; -- Игнорируем ошибки
                    END;
                END LOOP;
            END IF;
    END;
    RETURN v_player_id;
END get_or_create_player_id;
-- @function get_initial_position
-- @brief Returns the starting board position string based on rules.

FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
    v_rule      game_rules%ROWTYPE;
    v_error_msg VARCHAR2(255); 
BEGIN
    -- Сначала пытаемся найти правило
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
            p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN NULL;
    END;

    -- Проверяем РАЗМЕР ДОСКИ
    IF v_rule.board_size = 8 THEN
        -- 8x8 (Русские шашки: 64 символа)
        RETURN '+b+b+b+b' || -- Row 8
               'b+b+b+b+' || -- Row 7
               '+b+b+b+b' || -- Row 6
               '++++++++' || -- Row 5
               '++++++++' || -- Row 4
               'w+w+w+w+' || -- Row 3
               '+w+w+w+w' || -- Row 2
               'w+w+w+w+';   -- Row 1

    ELSIF v_rule.board_size = 10 THEN
        -- 10x10 (Международные шашки: 100 символов)
        -- Каждая строка должна содержать 10 символов
        -- Порядок: Row 10 (первые 10 символов) -> Row 1 (последние 10 символов)
        RETURN '+b+b+b+b+b' || -- Row 10 (10 символов: начинается с пустого, заканчивается фигурой)
               'b+b+b+b+b+' || -- Row 9 (10 символов: начинается с фигуры, заканчивается пустым)
               '+b+b+b+b+b' || -- Row 8 (10 символов: начинается с пустого, заканчивается фигурой)
               'b+b+b+b+b+' || -- Row 7 (10 символов: начинается с фигуры, заканчивается пустым)
               '++++++++++' || -- Row 6 (10 символов: все пустые)
               '++++++++++' || -- Row 5 (10 символов: все пустые)
               '+w+w+w+w+w' || -- Row 4 (10 символов: начинается с пустого, заканчивается фигурой)
               'w+w+w+w+w+' || -- Row 3 (10 символов: начинается с фигуры, заканчивается пустым)
               '+w+w+w+w+w' || -- Row 2 (10 символов: начинается с пустого, заканчивается фигурой)
               'w+w+w+w+w+';   -- Row 1 (10 символов: начинается с фигуры, заканчивается пустым)
    ELSE
        -- Неподдерживаемый размер
        v_error_msg := 'Правила с ID=' || p_rule_id || ' (Размер: ' || v_rule.board_size || ') не поддерживаются.';
        p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN NULL;
    END IF;
END get_initial_position;
-- @function idx_to_notation
-- @brief Converts a board index to its notation (e.g., 1 -> 'a1').
-- @dependencies:
--   - p_init_board_map (procedure)
--   - g_map_by_idx (global variable)

FUNCTION idx_to_notation(
    p_idx IN PLS_INTEGER, 
    p_board_size IN NUMBER -- <-- НОВЫЙ ПАРАМЕТР
) RETURN VARCHAR2 IS
BEGIN
    -- 1. Убедиться, что кэш нужного размера загружен
    p_init_board_map(p_board_size); 
    
    -- 2. Мгновенно получить нотацию из кэша по индексу
    RETURN g_map_by_idx(p_idx).notation;
    
EXCEPTION
    -- Если индекса нет (например, p_idx = 101), вернуть NULL
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END idx_to_notation;
-- @function find_capture_paths
-- @brief Recursively finds all possible capture paths from a starting position.
-- @dependencies:
--   - decode_board (function)
--   - p_init_board_map (procedure)
--   - p_audit_log (procedure)
--   - game_rules (table)
--   - c_black_man, c_black_king, c_white_man, c_white_king, c_empty_field (constants)
--   - g_map_by_idx (global variable)
--   - rec_board_field, t_move_list, t_move_path, r_move_step, r_move (types)

FUNCTION find_capture_paths(
    p_start_idx    IN PLS_INTEGER,
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_is_king      IN CHAR,
    p_rule_id      IN NUMBER,
    p_visited_path IN t_move_path DEFAULT t_move_path()
) RETURN t_move_list IS
    v_results             t_move_list := t_move_list();
    v_leaf_paths          t_move_list := t_move_list();
    v_opponent_man        CHAR(1);
    v_opponent_king       CHAR(1);
    v_decoded_board       VARCHAR2(128) := decode_board(p_board); -- 128 chars max
    
    v_rule                game_rules%ROWTYPE;
    v_board_size          PLS_INTEGER;
    v_total_squares       PLS_INTEGER;
    v_promotion_row       PLS_INTEGER;
    v_max_king_range      PLS_INTEGER;
    v_jump_directions     SYS.ODCINUMBERLIST;
    v_start_field         rec_board_field;
    
BEGIN
    -- 1. Инициализация параметров правил и доски
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_promotion_row   := v_board_size; -- 8 или 10
        v_max_king_range  := v_board_size - 1; 
        
        -- Обязательно инициализируем кэш перед использованием g_map_by_idx!
        p_init_board_map(v_board_size);
        
        v_start_field := g_map_by_idx(p_start_idx);

        IF v_board_size = 8 THEN
            v_jump_directions := SYS.ODCINUMBERLIST(-18, -14, 14, 18);
        ELSE -- 10x10
            v_jump_directions := SYS.ODCINUMBERLIST(-22, -18, 18, 22);
        END IF;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_audit_log(NULL, NULL, 'find_capture_paths: Rule ' || p_rule_id || ' not found.');
            RETURN v_results;
        WHEN OTHERS THEN
            p_audit_log(NULL, NULL, 'find_capture_paths error: ' || SQLERRM);
            RETURN v_results; 
    END;
    
    -- 2. Определение фигур противника
    IF p_player_color = 'W' THEN
        v_opponent_man  := c_black_man;
        v_opponent_king := c_black_king;
    ELSE
        v_opponent_man  := c_white_man;
        v_opponent_king := c_white_king;
    END IF;

    -- 3. Перебор направлений прыжка
    FOR i IN 1 .. v_jump_directions.COUNT LOOP
        DECLARE
            v_jump        PLS_INTEGER := v_jump_directions(i);
            v_land_idx    PLS_INTEGER;
            v_capture_idx PLS_INTEGER;
            v_is_visited  BOOLEAN := FALSE;
        BEGIN
            -- === ЛОГИКА ДЛЯ ПРОСТОЙ ===
            IF p_is_king = 'N' THEN
                v_land_idx    := p_start_idx + v_jump;
                v_capture_idx := p_start_idx + (v_jump / 2);

                -- Проверка границ и геометрии (через кэш)
                -- ABS(...) = 2 гарантирует, что мы не прыгнули "сквозь стену" (например, с h4 на a5)
                IF v_land_idx BETWEEN 1 AND v_total_squares 
                   AND g_map_by_idx.EXISTS(v_land_idx)
                   AND ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) = 2 
                THEN
                    -- Проверка содержимого клеток (куда прыгаем - пусто, кого бьем - враг)
                    IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field 
                       AND SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) 
                    THEN
                        -- Проверка на повторное взятие той же фигуры
                        FOR k IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(k).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;

                        IF NOT v_is_visited THEN
                            DECLARE
                                v_becomes_king        CHAR(1) := 'N';
                                v_land_row            PLS_INTEGER := g_map_by_idx(v_land_idx).row_num; 
                                v_is_promotion_square BOOLEAN := (p_player_color = 'W' AND v_land_row = v_promotion_row) 
                                                              OR (p_player_color = 'B' AND v_land_row = 1);
                                v_step                r_move_step;
                                v_new_path            t_move_path := p_visited_path;
                                v_sub_paths           t_move_list;
                                v_move                r_move;
                            BEGIN
                                v_step.start_idx    := p_start_idx;
                                v_step.end_idx      := v_land_idx;
                                v_step.captured_idx := v_capture_idx;
                                v_new_path.EXTEND;
                                v_new_path(v_new_path.LAST) := v_step;

                                -- В Русских шашках (ID 1) превращение происходит СРАЗУ, и бой продолжается уже дамкой
                                IF p_rule_id = 1 AND v_is_promotion_square THEN
                                    v_becomes_king := 'Y';
                                END IF;

                                -- Рекурсия
                                v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, v_becomes_king, p_rule_id, v_new_path);

                                IF v_sub_paths.COUNT = 0 THEN
                                    -- Листовой узел (больше бить некого)
                                    v_move.path          := v_new_path;
                                    v_move.is_capture    := 'Y';
                                    v_move.capture_count := v_new_path.COUNT;
                                    v_leaf_paths.EXTEND;
                                    v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                ELSE
                                    -- Добавляем все найденные продолжения
                                    FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                        v_results.EXTEND;
                                        v_results(v_results.LAST) := v_sub_paths(j);
                                    END LOOP;
                                END IF;
                            END;
                        END IF;
                    END IF;
                END IF;
                
            -- === ЛОГИКА ДЛЯ ДАМКИ ===
            ELSE 
                FOR k IN 1 .. v_max_king_range LOOP 
                    v_capture_idx := p_start_idx + (v_jump / 2 * k);

                    -- Проверка границ для "перелета" через пустые клетки до жертвы
                    IF v_capture_idx NOT BETWEEN 1 AND v_total_squares 
                       OR NOT g_map_by_idx.EXISTS(v_capture_idx)
                       OR ABS(v_start_field.col_num - g_map_by_idx(v_capture_idx).col_num) != k 
                    THEN
                        EXIT; -- Уперлись в край
                    END IF;

                    -- Нашли врага?
                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN
                        -- Проверка на повторное взятие
                        FOR m IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(m).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;
                        IF v_is_visited THEN EXIT; END IF; -- Нельзя бить ту же фигуру дважды

                        -- Ищем место приземления ЗА врагом
                        FOR l IN (k + 1) .. v_board_size LOOP 
                            v_land_idx := p_start_idx + (v_jump / 2 * l);
                            
                            IF v_land_idx NOT BETWEEN 1 AND v_total_squares 
                               OR NOT g_map_by_idx.EXISTS(v_land_idx)
                               OR ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) != l 
                            THEN
                                EXIT; -- Уперлись в край
                            END IF;
                            
                            -- Приземляться можно только на пустые клетки
                            IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field THEN
                                DECLARE
                                    v_step      r_move_step;
                                    v_new_path  t_move_path := p_visited_path;
                                    v_sub_paths t_move_list;
                                    v_move      r_move;
                                BEGIN
                                    v_step.start_idx    := p_start_idx;
                                    v_step.end_idx      := v_land_idx;
                                    v_step.captured_idx := v_capture_idx;
                                    v_new_path.EXTEND;
                                    v_new_path(v_new_path.LAST) := v_step;
                                    
                                    -- Рекурсия (дамка остается дамкой)
                                    v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, 'Y', p_rule_id, v_new_path);

                                    IF v_sub_paths.COUNT = 0 THEN
                                        v_move.path          := v_new_path;
                                        v_move.is_capture    := 'Y';
                                        v_move.capture_count := v_new_path.COUNT;
                                        v_leaf_paths.EXTEND;
                                        v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                    ELSE
                                        FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                            v_results.EXTEND;
                                            v_results(v_results.LAST) := v_sub_paths(j);
                                        END LOOP;
                                    END IF;
                                END;
                            ELSE
                                EXIT; -- Клетка занята, дальше прыгать по этой линии нельзя
                            END IF;
                        END LOOP;
                        EXIT; -- После нахождения первой фигуры на линии и проверки всех приземлений за ней - выходим из цикла по K
                    END IF;
                    
                    -- Если клетка не пустая и не враг (значит своя фигура) -> прерываем поиск в этом направлении
                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) != c_empty_field THEN
                        EXIT;
                    END IF;
                END LOOP; -- Конец цикла по дальности (k)
            END IF; -- Конец IF p_is_king
        END;
    END LOOP; -- Конец цикла по направлениям
    
    IF v_results.COUNT > 0 THEN
        RETURN v_results;
    ELSE
        RETURN v_leaf_paths;
    END IF;

END find_capture_paths;
-- @function find_all_player_moves
-- @brief Finds all legal moves for a given player.
-- @dependencies:
--   - decode_board (function)
--   - find_capture_paths (function)
--   - p_init_board_map (procedure)
--   - p_audit_log (procedure)
--   - game_rules (table)
--   - c_white_man, c_white_king, c_black_man, c_black_king, c_empty_field (constants)
--   - g_map_by_idx (global variable)
--   - t_move_list, r_move, r_move_step, rec_board_field (types)

FUNCTION find_all_player_moves(
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_rule_id      IN NUMBER
) RETURN t_move_list IS
    v_all_moves       t_move_list := t_move_list();
    v_capture_moves   t_move_list := t_move_list();
    v_simple_moves    t_move_list := t_move_list();
    v_player_man      CHAR(1);
    v_player_king     CHAR(1);
    v_max_captures    PLS_INTEGER := 0;
    v_decoded_board   VARCHAR2(128) := decode_board(p_board); -- Max 128
    
    v_rule            game_rules%ROWTYPE;
    v_board_size      PLS_INTEGER;
    v_total_squares   PLS_INTEGER;
    v_simple_move_w   SYS.ODCINUMBERLIST;
    v_simple_move_b   SYS.ODCINUMBERLIST;
    v_simple_move_all SYS.ODCINUMBERLIST;
    v_max_king_range  PLS_INTEGER;

BEGIN
    -- 1. Настройка параметров
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_max_king_range  := v_board_size - 1;
        
        p_init_board_map(v_board_size);
        
        IF v_board_size = 8 THEN
            v_simple_move_w   := SYS.ODCINUMBERLIST(-9, -7);
            v_simple_move_b   := SYS.ODCINUMBERLIST(7, 9);
            v_simple_move_all := SYS.ODCINUMBERLIST(-9, -7, 7, 9);
        ELSE -- 10x10
            v_simple_move_w   := SYS.ODCINUMBERLIST(-11, -9);
            v_simple_move_b   := SYS.ODCINUMBERLIST(9, 11);
            v_simple_move_all := SYS.ODCINUMBERLIST(-11, -9, 9, 11);
        END IF;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_audit_log(NULL, NULL, 'find_all_player_moves: Rule ' || p_rule_id || ' not found.');
            RETURN v_all_moves;
    END;

    IF p_player_color = 'W' THEN
        v_player_man  := c_white_man;
        v_player_king := c_white_king;
    ELSE
        v_player_man  := c_black_man;
        v_player_king := c_black_king;
    END IF;
    
    -- === 1. ПОИСК ВЗЯТИЙ (Captures) ===
    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece   CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_paths   t_move_list;
            v_is_king CHAR(1);
        BEGIN
            IF v_piece IN (v_player_man, v_player_king) THEN
                v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;
                
                v_paths := find_capture_paths(i, v_decoded_board, p_player_color, v_is_king, p_rule_id);
                
                IF v_paths.COUNT > 0 THEN
                    FOR j IN 1 .. v_paths.COUNT LOOP
                        v_capture_moves.EXTEND;
                        v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                        IF v_paths(j).capture_count > v_max_captures THEN
                            v_max_captures := v_paths(j).capture_count;
                        END IF;
                    END LOOP;
                END IF;
            END IF;
        END;
    END LOOP;

    -- === 2. ФИЛЬТРАЦИЯ ВЗЯТИЙ ===
    IF v_capture_moves.COUNT > 0 THEN
        -- Правило 1 (Русские): Обязательно бить, но можно выбрать ЛЮБОЕ количество
        IF p_rule_id = 1 THEN 
            RETURN v_capture_moves;
        ELSE 
        -- Правило 2 (Международные): Обязательно бить МАКСИМАЛЬНОЕ количество
            FOR i IN 1 .. v_capture_moves.COUNT LOOP
                IF v_capture_moves(i).capture_count = v_max_captures THEN
                    v_all_moves.EXTEND;
                    v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                END IF;
            END LOOP;
            RETURN v_all_moves;
        END IF;
    END IF;

    -- === 3. ПОИСК "ТИХИХ" ХОДОВ (Simple moves) ===
    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece       CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_start_field rec_board_field := g_map_by_idx(i); 
        BEGIN
            IF v_piece = v_player_man THEN
                DECLARE
                    v_directions SYS.ODCINUMBERLIST;
                BEGIN
                    IF p_player_color = 'W' THEN v_directions := v_simple_move_w;
                    ELSE v_directions := v_simple_move_b; END IF;
                    
                    FOR d IN 1 .. v_directions.COUNT LOOP
                        DECLARE
                            v_end_idx   PLS_INTEGER := i + v_directions(d);
                            v_end_field rec_board_field;
                        BEGIN
                            -- Проверяем границы и пустоту клетки
                            IF v_end_idx BETWEEN 1 AND v_total_squares 
                               AND g_map_by_idx.EXISTS(v_end_idx) 
                               AND SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field 
                            THEN
                                v_end_field := g_map_by_idx(v_end_idx);
                                -- Простая шашка ходит только на соседнюю клетку (разница колонок = 1)
                                IF ABS(v_start_field.col_num - v_end_field.col_num) = 1 THEN
                                    DECLARE
                                        v_move r_move;
                                        v_step r_move_step;
                                    BEGIN
                                        v_step.start_idx     := i;
                                        v_step.end_idx       := v_end_idx;
                                        v_step.captured_idx  := NULL;
                                        v_move.path          := t_move_path(v_step);
                                        v_move.is_capture    := 'N';
                                        v_move.capture_count := 0;
                                        v_simple_moves.EXTEND;
                                        v_simple_moves(v_simple_moves.LAST) := v_move;
                                    END;
                                END IF;
                            END IF;
                        END;
                    END LOOP;
                END;
                
            ELSIF v_piece = v_player_king THEN
                DECLARE
                    v_directions SYS.ODCINUMBERLIST := v_simple_move_all;
                BEGIN
                    FOR d IN 1 .. v_directions.COUNT LOOP
                        FOR k IN 1 .. v_max_king_range LOOP 
                            DECLARE
                                v_end_idx   PLS_INTEGER := i + (v_directions(d) * k);
                                v_end_field rec_board_field;
                            BEGIN
                                IF NOT g_map_by_idx.EXISTS(v_end_idx) THEN EXIT; END IF;
                                v_end_field := g_map_by_idx(v_end_idx);
                                
                                -- Проверка геометрии (чтобы не перепрыгнуть через край на другую строку)
                                -- Если это не первый шаг, проверяем связность с предыдущей клеткой
                                IF k > 1 AND ABS(g_map_by_idx(i + (v_directions(d) * (k - 1))).col_num - v_end_field.col_num) != 1 THEN
                                    EXIT;
                                END IF;

                                IF SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                    DECLARE
                                        v_move r_move;
                                        v_step r_move_step;
                                    BEGIN
                                        v_step.start_idx     := i;
                                        v_step.end_idx       := v_end_idx;
                                        v_step.captured_idx  := NULL;
                                        v_move.path          := t_move_path(v_step);
                                        v_move.is_capture    := 'N';
                                        v_move.capture_count := 0;
                                        v_simple_moves.EXTEND;
                                        v_simple_moves(v_simple_moves.LAST) := v_move;
                                    END;
                                ELSE
                                    EXIT; -- Клетка занята, дальше идти нельзя
                                END IF;
                            END;
                        END LOOP;
                    END LOOP;
                END;
            END IF;
        END;
    END LOOP;

    RETURN v_simple_moves;
END find_all_player_moves;
-- @function get_sorted_possible_moves
-- @brief Gets all possible moves and sorts them based on a heuristic score.
-- @dependencies:
--   - find_all_player_moves (function)
--   - t_move_list, r_move (types)

FUNCTION get_sorted_possible_moves(
    p_board   IN VARCHAR2,
    p_color   IN CHAR,
    p_rule_id IN NUMBER
) RETURN t_move_list IS
    v_moves t_move_list;
    v_temp  r_move; -- A temporary record for swapping
BEGIN
    v_moves := find_all_player_moves(p_board, p_color, p_rule_id);
    
    IF v_moves.COUNT < 2 THEN
        RETURN v_moves; -- No need to sort if 0 or 1 move
    END IF;

    -- Assign a score to each move
    FOR i IN 1..v_moves.COUNT LOOP
        v_moves(i).score := 0;
        -- Highest priority: Captures. More captures are better.
        IF v_moves(i).is_capture = 'Y' THEN
            v_moves(i).score := 1000 + v_moves(i).capture_count;
        END IF;
    END LOOP;
    
    -- Sort the collection in PL/SQL using a simple bubble sort
    FOR i IN 1 .. v_moves.COUNT - 1 LOOP
        FOR j IN i + 1 .. v_moves.COUNT LOOP
            -- If the current move has a lower score than the next one, swap them
            IF v_moves(i).score < v_moves(j).score THEN
                v_temp := v_moves(i);
                v_moves(i) := v_moves(j);
                v_moves(j) := v_temp;
            END IF;
        END LOOP;
    END LOOP;

    RETURN v_moves;

END get_sorted_possible_moves;
-- @function evaluate_board
-- @brief Assigns a numerical score to a given board position.
-- @dependencies:
--   - p_init_board_map (procedure)
--   - c_empty_field (constant)
--   - g_map_by_idx (global variable)
--   - rec_board_field (type)

FUNCTION evaluate_board(
    p_board      IN VARCHAR2,
    p_ai_color   IN CHAR,
    p_difficulty IN CHAR
) RETURN NUMBER IS
    v_score          NUMBER := 0;
    v_piece          CHAR(1);
    
    v_total_squares  PLS_INTEGER;
    v_board_size     PLS_INTEGER;
    
    c_man_value      CONSTANT NUMBER := 10;
    c_king_value     CONSTANT NUMBER := 50;
    c_side_val       CONSTANT NUMBER := 20; 
    c_wall_val       CONSTANT NUMBER := 10; 
    
    -- Переменные для проверки условия победы
    v_ai_pieces_cnt  PLS_INTEGER := 0;
    v_opp_pieces_cnt PLS_INTEGER := 0;

BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    
    p_init_board_map(v_board_size);

    FOR i IN 1..v_total_squares LOOP
        v_piece := SUBSTR(p_board, i, 1);
        
        IF v_piece != c_empty_field THEN
            DECLARE
                v_piece_value    NUMBER;
                v_multiplier     NUMBER;
                v_piece_color    CHAR(1);
                
                v_field_rec      rec_board_field := g_map_by_idx(i);
                v_row            PLS_INTEGER     := v_field_rec.row_num;
                v_col            PLS_INTEGER     := v_field_rec.col_num;
                
                v_position_bonus NUMBER := 0;
            BEGIN
                -- Определяем цвет
                v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                
                -- Считаем фигуры для проверки конца игры
                IF v_piece_color = p_ai_color THEN
                    v_ai_pieces_cnt := v_ai_pieces_cnt + 1;
                ELSE
                    v_opp_pieces_cnt := v_opp_pieces_cnt + 1;
                END IF;

                -- Оценка материала
                v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                
                v_score := v_score + (v_piece_value * v_multiplier);

                IF p_difficulty != 'H' THEN
                    -- Бонус за борт
                    IF v_col = 1 OR v_col = v_board_size THEN
                        v_position_bonus := v_position_bonus + c_side_val;
                    END IF;

                    -- Бонус за продвижение
                    IF v_piece_color = 'W' THEN
                        v_position_bonus := v_position_bonus + ( (v_row / v_board_size) * c_wall_val );
                    ELSE -- Piece is Black
                        v_position_bonus := v_position_bonus + ( (( (v_board_size + 1) - v_row) / v_board_size) * c_wall_val );
                    END IF;
                END IF;
                
                v_score := v_score + (v_position_bonus * v_multiplier);
            END;
        END IF;
    END LOOP;
    
    -- Проверка терминального состояния (Победа/Поражение)
    IF v_ai_pieces_cnt > 0 AND v_opp_pieces_cnt = 0 THEN
        RETURN 9999; -- AI has won
    ELSIF v_ai_pieces_cnt = 0 AND v_opp_pieces_cnt > 0 THEN
        RETURN -9999; -- AI has lost
    END IF;

    RETURN v_score;
END evaluate_board;
-- @function apply_move_to_board
-- @brief Simulates a move and returns the new board state as a string.
-- @dependencies:
--   - p_init_board_map (procedure)
--   - p_audit_log (procedure)
--   - c_empty_field, c_white_man, c_black_man, c_white_king, c_black_king (constants)
--   - g_map_by_idx (global variable)
--   - r_move (type)

FUNCTION apply_move_to_board(
    p_board IN VARCHAR2,
    p_move  IN r_move,
    p_color IN CHAR
) RETURN VARCHAR2 IS
    v_new_board    VARCHAR2(128) := p_board; -- Было 200 -> Стало 128
    v_moving_piece CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
    v_start_pos    PLS_INTEGER := p_move.path(1).start_idx;
    v_end_pos      PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
    v_promoted     BOOLEAN := FALSE;
    
    v_total_squares PLS_INTEGER;
    v_board_size    PLS_INTEGER;
BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    p_init_board_map(v_board_size);

    -- Очистка старой позиции
    v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

    -- Удаление срубленных шашек
    IF p_move.is_capture = 'Y' THEN
        FOR i IN 1..p_move.path.COUNT LOOP
            v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
        END LOOP;
    END IF;

    -- Превращение в дамку
    IF v_moving_piece IN (c_white_man, c_black_man) THEN
        DECLARE
            v_end_row PLS_INTEGER := g_map_by_idx(v_end_pos).row_num;
            v_is_promotion BOOLEAN := (p_color = 'W' AND v_end_row = v_board_size) OR (p_color = 'B' AND v_end_row = 1);
        BEGIN
            IF v_is_promotion THEN
                v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
            END IF;
        END;
    END IF;

    -- Установка фигуры на новое место
    v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
    RETURN v_new_board;
    
EXCEPTION
    WHEN OTHERS THEN
        p_audit_log(NULL, NULL, 'apply_move_to_board: Error ' || SQLERRM);
        RETURN p_board; 
END apply_move_to_board;
-- @function minimax
-- @brief The core recursive Minimax algorithm with Alpha-Beta Pruning.
-- @dependencies:
--   - get_sorted_possible_moves (function)
--   - evaluate_board (function)
--   - apply_move_to_board (function)
--   - r_minimax_result, t_move_list (types)

FUNCTION minimax(
    p_board         IN VARCHAR2,
    p_depth         IN PLS_INTEGER,
    p_alpha         IN NUMBER, 
    p_beta          IN NUMBER, 
    p_is_maximizing IN BOOLEAN,
    p_ai_color      IN CHAR,
    p_difficulty    IN CHAR,
    p_rule_id       IN NUMBER
) RETURN r_minimax_result IS
    v_result         r_minimax_result;
    v_possible_moves t_move_list; 
    v_current_color  CHAR(1);
    v_local_alpha    NUMBER := p_alpha;
    v_local_beta     NUMBER := p_beta;
BEGIN
    v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;
    
    v_possible_moves := get_sorted_possible_moves(
        p_board   => p_board, 
        p_color   => v_current_color, 
        p_rule_id => p_rule_id
    );

    IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN
        v_result.score := evaluate_board(p_board, p_ai_color, p_difficulty);
        v_result.move := NULL;
        RETURN v_result;
    END IF;
    
    IF p_is_maximizing THEN
        v_result.score := -99999; 
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(128) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color); -- Было 200
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => FALSE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );
                
                IF v_eval_result.score > v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;
                
                v_local_alpha := GREATEST(v_local_alpha, v_eval_result.score);
                
                IF v_local_beta <= v_local_alpha THEN
                    EXIT; -- Pruning
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    ELSE -- Minimizing player
        v_result.score := 99999;
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(128) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color); -- Было 200
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => TRUE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );

                IF v_eval_result.score < v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;

                v_local_beta := LEAST(v_local_beta, v_eval_result.score);

                IF v_local_beta <= v_local_alpha THEN
                    EXIT; -- Pruning
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    END IF;
END minimax;
-- @function get_ai_move
-- @brief Main entry point for the AI to get its best move.
-- @dependencies:
--   - decode_board (function)
--   - p_init_board_map (procedure)
--   - minimax (function)
--   - find_all_player_moves (function)
--   - idx_to_notation (function)
--   - r_move, r_minimax_result, t_move_list (types)

FUNCTION get_ai_move(
    p_board_position IN game_moves.board_position%TYPE, -- ИСПРАВЛЕНО: game_moves вместо games
    p_ai_color       IN games.current_turn%TYPE,
    p_rule_id        IN games.rule_id%TYPE,
    p_difficulty     IN games.ai_difficulty%TYPE
) RETURN VARCHAR2 IS
    v_best_move_str  VARCHAR2(100);
    v_chosen_move    r_move;
    v_decoded_board  VARCHAR2(128) := decode_board(p_board_position);
    v_search_depth   PLS_INTEGER;
    v_minimax_result r_minimax_result;
    v_alpha          NUMBER;
    v_beta           NUMBER;
    v_board_size     PLS_INTEGER;
BEGIN
    v_board_size := SQRT(LENGTH(v_decoded_board));
    p_init_board_map(v_board_size);
    
    v_search_depth := CASE p_difficulty
                        WHEN 'E' THEN 4
                        WHEN 'M' THEN 8
                        WHEN 'H' THEN 12
                        ELSE 2
                      END;
    v_alpha := -99999;
    v_beta  := 99999;

    v_minimax_result := minimax(
        p_board         => v_decoded_board, 
        p_depth         => v_search_depth, 
        p_alpha         => v_alpha, 
        p_beta          => v_beta, 
        p_is_maximizing => TRUE, 
        p_ai_color      => p_ai_color, 
        p_difficulty    => p_difficulty,
        p_rule_id       => p_rule_id
    );
    v_chosen_move := v_minimax_result.move;

    IF p_difficulty = 'E' AND DBMS_RANDOM.VALUE < 0.25 THEN
         DECLARE
            v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
            IF v_random_moves.COUNT > 0 THEN
                 v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
            END IF;
         END;
     END IF;

    -- Формирование строки хода
    IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
         v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx, v_board_size);
         FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
             v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                              || idx_to_notation(v_chosen_move.path(j).end_idx, v_board_size);
         END LOOP;
    ELSE
        -- Fallback, если Minimax вернул NULL
         DECLARE
            v_fallback_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
             IF v_fallback_moves.COUNT > 0 THEN
                  v_chosen_move := v_fallback_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_fallback_moves.COUNT + 1)));
                  v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx, v_board_size);
                  FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
                      v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                                       || idx_to_notation(v_chosen_move.path(j).end_idx, v_board_size);
                  END LOOP;
             ELSE
                  v_best_move_str := NULL;
             END IF;
         END;
    END IF;

    RETURN v_best_move_str;
END get_ai_move;
-- @function f_get_board_as_clob
-- @brief Returns a CLOB representing the board for display.
-- @dependencies:
--   - decode_board (function)
--   - p_init_board_map (procedure)
--   - c_empty_field (constant)
--   - t_map_indices (type)

FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2,
    p_highlight_indices IN t_map_indices DEFAULT t_map_indices()
) RETURN CLOB IS
    v_clob          CLOB;
    v_char          CHAR(1);
    v_linear_idx    PLS_INTEGER;
    v_decoded_board VARCHAR2(128) := decode_board(p_board_position); -- Было 200
    c_nl CONSTANT   VARCHAR2(1)   := CHR(10);
    
    v_board_size    PLS_INTEGER;
    v_total_squares PLS_INTEGER;
    v_header        VARCHAR2(128) := '  |'; -- Было 200
    v_separator     VARCHAR2(128) := '--+'; -- Было 200
    
BEGIN
    DBMS_LOB.createtemporary(v_clob, TRUE);

    v_total_squares := LENGTH(v_decoded_board);
    v_board_size    := SQRT(v_total_squares);
    
    IF v_board_size != TRUNC(v_board_size) THEN 
        DBMS_LOB.append(v_clob, 'ОШИБКА: Длина доски (' || v_total_squares || ') не является полным квадратом.');
        RETURN v_clob;
    END IF;
    
    p_init_board_map(v_board_size);
    
    FOR c IN 1 .. v_board_size LOOP
        -- Для доски 10x10 нужна буква 'j' (a-i, затем j)
        DECLARE
            v_col_letter CHAR(1);
        BEGIN
            IF c <= 9 THEN
                v_col_letter := CHR(ASCII('A') + c - 1);
            ELSE
                -- Для 10-й колонки используем 'J' (или можно 'j', но обычно заглавные)
                v_col_letter := 'J';
            END IF;
            v_header    := v_header    || ' ' || v_col_letter || ' ';
            v_separator := v_separator || '---';
        END;
    END LOOP;
    v_header    := v_header    || ' |';
    v_separator := v_separator || '+--';

    DBMS_LOB.append(v_clob, v_header || c_nl);
    DBMS_LOB.append(v_clob, v_separator || c_nl);

    FOR r IN REVERSE 1 .. v_board_size LOOP
        DBMS_LOB.append(v_clob, LPAD(r, 2, ' ') || '|');
        FOR c IN 1 .. v_board_size LOOP
            v_linear_idx := ((v_board_size - r) * v_board_size) + c;
            
            IF MOD(r + c, 2) = 0 THEN
                v_char := SUBSTR(v_decoded_board, v_linear_idx, 1);
                IF v_char = c_empty_field OR v_char IS NULL THEN
                     IF p_highlight_indices.EXISTS(v_linear_idx) THEN
                         DBMS_LOB.append(v_clob, '[.]');
                     ELSE
                         DBMS_LOB.append(v_clob, '[ ]');
                     END IF;
                ELSE
                    DBMS_LOB.append(v_clob, '[' || v_char || ']');
                END IF;
            ELSE
                DBMS_LOB.append(v_clob, '   ');
            END IF;
        END LOOP;
        DBMS_LOB.append(v_clob, '| ' || r);
        DBMS_LOB.append(v_clob, c_nl);
    END LOOP;
    
    DBMS_LOB.append(v_clob, v_separator || c_nl);
    DBMS_LOB.append(v_clob, v_header || c_nl);
    RETURN v_clob;
    
EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_LOB.istemporary(v_clob) = 1 THEN
            DBMS_LOB.freetemporary(v_clob);
        END IF;
        DBMS_LOB.createtemporary(v_clob, TRUE);
        DBMS_LOB.append(v_clob, 'КРИТИЧЕСКАЯ ОШИБКА в f_get_board_as_clob: ' || SQLERRM);
        RETURN v_clob;
END f_get_board_as_clob;
-- @procedure p_init_board_map
-- @brief Initializes global cache maps for board coordinates (Index <-> Notation).
-- @dependencies: global variables g_map_by_notation, g_map_by_idx, g_current_map_size

PROCEDURE p_init_board_map(p_board_size IN NUMBER) IS
    v_idx       PLS_INTEGER;
    v_notation  VARCHAR2(10);
    v_field_rec rec_board_field;
BEGIN
    -- 1. Проверяем кэш. Если карта нужного размера уже загружена, выходим.
    IF p_board_size = g_current_map_size THEN
        RETURN;
    END IF;
    
    -- 2. Очищаем старые карты
    g_map_by_notation.DELETE;
    g_map_by_idx.DELETE;
    
    -- 3. Генерируем новые карты
    FOR r IN 1 .. p_board_size LOOP
        FOR c IN 1 .. p_board_size LOOP
            -- Формула индекса: Сверху-вниз (строка 1 в строке = 8/10 ряд на доске)
            -- Нотация 'a1' находится в конце строки (для 8x8 это индекс 57..64)
            v_idx := ((p_board_size - r) * p_board_size) + c;
            
            -- Нотация (например, 'a1', 'h8', 'j10')
            -- ASCII('a') = 97. Для c=1 -> 'a', c=8 -> 'h', c=10 -> 'j'.
            v_notation := CHR(ASCII('a') + c - 1) || r;

            -- Собираем запись
            v_field_rec.idx      := v_idx;
            v_field_rec.notation := v_notation;
            v_field_rec.row_num  := r;
            v_field_rec.col_num  := c;

            -- Заполняем ОБЕ карты
            g_map_by_notation(v_notation) := v_field_rec;
            g_map_by_idx(v_idx)           := v_field_rec;
            
        END LOOP;
    END LOOP;
    
    -- 4. Обновляем "флаг" кэша
    g_current_map_size := p_board_size;
    
END p_init_board_map;
-- @procedure p_audit_log
-- @brief Logs an audit event into the audit_log table.
-- @dependencies:
--   - audit_log (table)

PROCEDURE p_audit_log(
    p_player_id  IN players.player_id%TYPE,
    p_game_id    IN games.game_id%TYPE,
    p_event_msg  IN audit_log.event_msg%TYPE
) IS PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log (
        player_id, 
        game_id, 
        event_msg
    )
    VALUES (
        p_player_id, 
        p_game_id, 
        SUBSTR(p_event_msg, 1, 2000)
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN NULL; -- Ошибки логирования игнорируем
END p_audit_log;
-- @procedure p_update_ratings
-- @brief Updates player ratings after a game is finished.
-- @dependencies:
--   - (none)

-- [РЕАЛИЗАЦИЯ] +5 Puzzle, +16 Win, -16 Loss, Min 0.

PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
    v_game      games%ROWTYPE;
    v_season_id seasons.season_id%TYPE;

    -- Внутренняя процедура для атомарного обновления одного игрока
    PROCEDURE update_one_player(p_pid IN NUMBER, p_delta IN NUMBER) IS
        v_current_rating NUMBER;
    BEGIN
        IF p_pid IS NULL THEN RETURN; END IF; -- ИИ рейтинг не обновляем

        -- 1. Ищем текущий рейтинг или создаем запись, если её нет (Star 500)
        BEGIN
            SELECT rating INTO v_current_rating
            FROM player_ratings
            WHERE player_id = p_pid 
              AND rule_id = v_game.rule_id 
              AND season_id = v_season_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_current_rating := 500;
                INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                VALUES (p_pid, v_game.rule_id, v_season_id, v_current_rating);
        END;

        -- 2. Обновляем (не уходим ниже 0)
        UPDATE player_ratings
        SET rating = GREATEST(0, rating + p_delta)
        WHERE player_id = p_pid 
          AND rule_id = v_game.rule_id 
          AND season_id = v_season_id;
    END;

BEGIN
    -- Получаем данные игры
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN;
    END;

    -- Определяем текущий сезон (берем последний активный или просто максимальный ID)
    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE SYSDATE BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Если сезона нет, берем последний созданный (fallback)
            BEGIN
                SELECT MAX(season_id) INTO v_season_id FROM seasons;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_season_id := NULL;
            END;
            
            -- Если вообще нет сезонов, создаем начальный сезон автоматически
            IF v_season_id IS NULL THEN
                DECLARE
                    v_current_month DATE := TRUNC(SYSDATE, 'MM');
                    v_next_month DATE := ADD_MONTHS(v_current_month, 1);
                    v_season_name VARCHAR2(100);
                    v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
                    );
                    v_month_num PLS_INTEGER;
                    v_year_num PLS_INTEGER;
                BEGIN
                    v_month_num := EXTRACT(MONTH FROM v_current_month);
                    v_year_num := EXTRACT(YEAR FROM v_current_month);
                    v_season_name := v_month_names(v_month_num) || '-' || v_year_num;
                    
                    INSERT INTO seasons (season_name, start_date, end_date)
                    VALUES (v_season_name, v_current_month, v_next_month - 1)
                    RETURNING season_id INTO v_season_id;
                    
                    COMMIT;
                EXCEPTION
                    WHEN OTHERS THEN
                        -- Если не удалось создать сезон, выходим
                        RETURN;
                END;
            END IF;
    END;

    -- Логика начисления
    IF v_game.status = 'V' THEN -- Victory (Кто-то выиграл)
        
        -- СЛУЧАЙ А: ПАЗЛ (Puzzle / Daily)
        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
                v_puzzle_created_by NUMBER;
            BEGIN
                -- Кто решал? (В пазлах играет создатель сессии)
                v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
                
                -- Проверяем, является ли пазл общим (не созданным пользователем)
                BEGIN
                    SELECT created_by_player_id INTO v_puzzle_created_by
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_puzzle_created_by := NULL;
                END;
                
                -- Рейтинг обновляется только для общих пазлов (created_by_player_id IS NULL)
                IF v_puzzle_created_by IS NULL THEN
                    -- Проверяем, решал ли он эту задачу РАНЬШЕ (успешно)
                    SELECT COUNT(*) INTO v_prev_solves
                    FROM games
                    WHERE puzzle_id = v_game.puzzle_id
                      AND (player_white_id = v_solver_id OR player_black_id = v_solver_id)
                      AND status = 'V'
                      AND game_id != p_game_id; -- Исключаем текущую сессию

                    -- Если решил впервые -> +5 очков
                    IF v_prev_solves = 0 THEN
                        update_one_player(v_solver_id, 5);
                    END IF;
                END IF;
            END;

        -- СЛУЧАЙ Б: ОБЫЧНАЯ ИГРА (PvP / PvE)
        ELSE
            -- Рейтинг обновляется только для PvP игр (не для PvE против AI)
            IF v_game.ai_difficulty IS NULL THEN
                -- Это PvP игра - обновляем рейтинг
                IF v_game.winner_player_color = 'W' THEN
                    update_one_player(v_game.player_white_id, 16); -- Победитель
                    update_one_player(v_game.player_black_id, -16); -- Проигравший
                ELSIF v_game.winner_player_color = 'B' THEN
                    update_one_player(v_game.player_black_id, 16); -- Победитель
                    update_one_player(v_game.player_white_id, -16); -- Проигравший
                END IF;
            END IF;
            -- Если ai_difficulty IS NOT NULL - это PvE против AI, рейтинг НЕ обновляется
        END IF;
        
    END IF;
    -- При ничьей (status = 'D') очки не меняются (согласно твоему описанию).
    
    -- Обработка матчей: создание следующей игры или завершение матча
    IF v_game.match_id IS NOT NULL THEN
        p_process_match_continuation(v_game.match_id, p_game_id);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- Рейтинг не должен валить игру, просто логируем ошибку
        p_audit_log(NULL, p_game_id, 'RATING_ERROR: ' || SQLERRM);
END p_update_ratings;
-- @procedure p_process_match_continuation
-- @brief Processes match continuation: creates next game or completes match
PROCEDURE p_process_match_continuation(p_match_id IN NUMBER, p_completed_game_id IN NUMBER) IS
    v_match matches%ROWTYPE;
    v_completed_game games%ROWTYPE;
    v_player1_id players.player_id%TYPE;
    v_player2_id players.player_id%TYPE;
    v_player1_wins NUMBER := 0;
    v_player2_wins NUMBER := 0;
    v_games_to_win NUMBER;
    v_next_game_id NUMBER;
    v_next_player_color CHAR(1);
    v_error_msg VARCHAR2(255);
BEGIN
    -- Получаем данные матча
    BEGIN
        SELECT * INTO v_match FROM matches WHERE match_id = p_match_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN; -- Матч не найден, выходим
    END;
    
    -- Если матч уже завершен, ничего не делаем
    IF v_match.status = 'C' THEN
        RETURN;
    END IF;
    
    -- Получаем данные завершенной игры
    BEGIN
        SELECT * INTO v_completed_game FROM games WHERE game_id = p_completed_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;
    
    -- Определяем игроков матча из первой игры
    DECLARE
        v_first_game games%ROWTYPE;
    BEGIN
        SELECT * INTO v_first_game 
        FROM games 
        WHERE match_id = p_match_id 
        ORDER BY game_id ASC 
        FETCH FIRST 1 ROW ONLY;
        
        v_player1_id := v_first_game.player_white_id;
        v_player2_id := v_first_game.player_black_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;
    
    -- Подсчитываем победы каждого игрока в матче
    FOR r IN (
        SELECT winner_player_color, status
        FROM games
        WHERE match_id = p_match_id
          AND status IN ('V', 'D', 'T', 'R')
    ) LOOP
        IF r.status = 'V' THEN
            IF r.winner_player_color = 'W' AND v_player1_id IS NOT NULL THEN
                v_player1_wins := v_player1_wins + 1;
            ELSIF r.winner_player_color = 'B' AND v_player2_id IS NOT NULL THEN
                v_player2_wins := v_player2_wins + 1;
            END IF;
        END IF;
    END LOOP;
    
    v_games_to_win := v_match.games_to_win;
    
    -- Проверяем, достиг ли кто-то нужного количества побед
    IF v_player1_wins >= v_games_to_win THEN
        -- Игрок 1 выиграл матч
        UPDATE matches
        SET status = 'C',
            winner_player_id = v_player1_id
        WHERE match_id = p_match_id;
        p_audit_log(v_player1_id, p_completed_game_id, 'MATCH_WON');
        RETURN;
    ELSIF v_player2_wins >= v_games_to_win THEN
        -- Игрок 2 выиграл матч
        UPDATE matches
        SET status = 'C',
            winner_player_id = v_player2_id
        WHERE match_id = p_match_id;
        p_audit_log(v_player2_id, p_completed_game_id, 'MATCH_WON');
        RETURN;
    END IF;
    
    -- Если никто не выиграл, создаем следующую игру с чередованием цвета
    -- Определяем цвет для следующей игры (чередуем)
    DECLARE
        v_game_count NUMBER;
        v_creator_id players.player_id%TYPE;
        v_opponent_id players.player_id%TYPE;
    BEGIN
        SELECT COUNT(*) INTO v_game_count
        FROM games
        WHERE match_id = p_match_id;
        
        -- Четная игра (2, 4, 6...) - первый игрок играет черными, второй белыми
        -- Нечетная игра (1, 3, 5...) - первый игрок играет белыми, второй черными
        IF MOD(v_game_count, 2) = 0 THEN
            -- Следующая игра: первый игрок черными, второй белыми
            v_creator_id := v_player1_id;
            v_opponent_id := v_player2_id;
            v_next_player_color := 'B';
        ELSE
            -- Следующая игра: первый игрок белыми, второй черными
            v_creator_id := v_player1_id;
            v_opponent_id := v_player2_id;
            v_next_player_color := 'W';
        END IF;
        
        -- Получаем параметры из первой игры матча
        DECLARE
            v_first_game games%ROWTYPE;
        BEGIN
            SELECT * INTO v_first_game
            FROM games
            WHERE match_id = p_match_id
            ORDER BY game_id ASC
            FETCH FIRST 1 ROW ONLY;
            
            -- Создаем следующую игру напрямую через INSERT
            INSERT INTO games (
                match_id, rule_id, player_white_id, player_black_id,
                creator_player_color, status, current_turn,
                time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                p_match_id, v_first_game.rule_id,
                CASE v_next_player_color WHEN 'W' THEN v_creator_id ELSE v_opponent_id END,
                CASE v_next_player_color WHEN 'W' THEN v_opponent_id ELSE v_creator_id END,
                v_next_player_color, 'C', 'W', -- Статус 'C' (Challenged), так как нужно присоединение
                v_first_game.time_limit_move_sec,
                v_first_game.time_limit_game_sec,
                v_first_game.draw_moves_limit,
                v_first_game.enable_pos_repetition_draw
            )
            RETURNING game_id INTO v_next_game_id;
            
            p_audit_log(v_creator_id, v_next_game_id, 'MATCH_NEXT_GAME_CREATED');
        END;
    END;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Ошибки при обработке матча не должны влиять на основную логику
        p_audit_log(NULL, p_completed_game_id, 'MATCH_CONTINUATION_ERROR: ' || SQLERRM);
END p_process_match_continuation;
-- @procedure p_process_move
-- @brief Processes a player's move, validates it, and updates the game state.
-- @dependencies:
--   - games (table)
--   - game_rules (table)
--   - game_moves (table)
--   - spectators (table)
--   - p_init_board_map (procedure)
--   - decode_board (function)
--   - find_all_player_moves (function)
--   - p_update_ratings (procedure)
--   - idx_to_notation (function)
--   - p_audit_log (procedure)
--   - encode_board (function)
--   - c_white_man, c_black_man, c_white_king, c_black_king, c_empty_field (constants)
--   - t_move_list, r_move (types)

PROCEDURE p_process_move(
    p_game_id        IN NUMBER,
    p_move_notation  IN VARCHAR2,
    p_player_id      IN NUMBER, 
    p_status_message OUT VARCHAR2
) IS
    v_game              games%ROWTYPE;
    v_player_color      CHAR(1);
    v_all_legal_moves   t_move_list;
    v_chosen_move       r_move;
    v_is_move_valid     BOOLEAN := FALSE;
    v_move_count        NUMBER;
    v_error_msg         VARCHAR2(2000);
    
    v_board_size        PLS_INTEGER;
    v_decoded_board     VARCHAR2(128); -- Явный тип вместо %TYPE для надежности
    v_new_board_decoded VARCHAR2(128);
    v_new_board_encoded VARCHAR2(128); -- Явный тип
    
BEGIN
    -- Блокируем игру для обновления
    SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
    
    -- Инициализация карты
    BEGIN
        SELECT r.board_size INTO v_board_size 
        FROM game_rules r 
        WHERE r.rule_id = v_game.rule_id;
        
        p_init_board_map(v_board_size);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status_message := 'Критическая ошибка: Правило ' || v_game.rule_id || ' не найдено.';
            ROLLBACK;
            RETURN;
    END;

    -- Получаем текущую позицию доски: из последнего хода или начальная позиция
    BEGIN
        SELECT board_position INTO v_decoded_board
        FROM game_moves
        WHERE game_id = p_game_id
        ORDER BY move_number DESC
        FETCH FIRST 1 ROW ONLY;
        v_decoded_board := decode_board(v_decoded_board);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Если ходов нет, используем начальную позицию
            v_decoded_board := get_initial_position(v_game.rule_id);
            IF v_decoded_board IS NULL THEN
                p_status_message := 'Критическая ошибка: Не удалось получить начальную позицию.';
                ROLLBACK;
                RETURN;
            END IF;
    END;

    -- Проверка лимита времени на партию
    IF v_game.time_limit_game_sec IS NOT NULL THEN
        DECLARE
            v_elapsed_sec NUMBER := (SYSDATE - v_game.start_time) * 86400;
        BEGIN
            IF v_elapsed_sec >= v_game.time_limit_game_sec THEN
                p_drop_move_timeout_job(p_game_id);
                UPDATE games 
                SET status = 'T', 
                    end_time = SYSDATE,
                    winner_player_color = CASE 
                        WHEN v_game.current_turn = 'W' THEN 'B' 
                        ELSE 'W' 
                    END
                WHERE game_id = p_game_id;
                p_status_message := 'Игра завершена по таймауту (превышен лимит времени на партию: ' || v_game.time_limit_game_sec || ' сек).';
                UPDATE spectators SET left_at = SYSDATE WHERE game_id = p_game_id AND left_at IS NULL;
                p_audit_log(NULL, p_game_id, 'GAME_TIMEOUT');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;
        END;
    END IF;

    -- Определение цвета текущего игрока
    IF v_game.ai_difficulty IS NOT NULL THEN
        v_player_color := v_game.current_turn;
    ELSE
        IF v_game.player_white_id = p_player_id THEN
            v_player_color := 'W';
        ELSE
            v_player_color := 'B';
        END IF;
    END IF;

    -- Поиск всех легальных ходов
    v_all_legal_moves := find_all_player_moves(v_decoded_board, v_player_color, v_game.rule_id);

    -- Если ходов нет -> Поражение
    IF v_all_legal_moves.COUNT = 0 THEN
        p_drop_move_timeout_job(p_game_id);
        
        UPDATE games
        SET status              = 'V',
            end_time            = SYSDATE,
            winner_player_color = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            -- [ВАЖНО] Если это пазл и мы проиграли (ходов нет), ставим 'f' (failed)
            puzzle_status       = CASE WHEN puzzle_id IS NOT NULL THEN 'f' ELSE puzzle_status END
        WHERE game_id = p_game_id;
        
        p_status_message := 'Ходов нет. Вы проиграли!';
        p_update_ratings(p_game_id);
        COMMIT;
        RETURN;
    END IF;
    
    -- Валидация хода игрока (сравнение нотации)
    FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
        DECLARE
            v_legal_move r_move := v_all_legal_moves(i);
            v_notation   VARCHAR2(100);
        BEGIN
            v_notation := idx_to_notation(v_legal_move.path(1).start_idx, v_board_size);
            FOR j IN 1 .. v_legal_move.path.COUNT LOOP
                v_notation := v_notation || CASE v_legal_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                              || idx_to_notation(v_legal_move.path(j).end_idx, v_board_size);
            END LOOP;
            
            IF REPLACE(LOWER(p_move_notation), 'x', ':') = v_notation THEN
                v_chosen_move   := v_legal_move;
                v_is_move_valid := TRUE;
                EXIT;
            END IF;
        END;
    END LOOP;

    -- Если ход невалиден -> Вывод ошибки и подсказок
    IF NOT v_is_move_valid THEN
        IF v_all_legal_moves.COUNT > 0 AND v_all_legal_moves(1).is_capture = 'Y' THEN
            DECLARE
                v_notation_str VARCHAR2(4000);
            BEGIN
                v_error_msg := 'Неверный ход. Взятие обязательно! Доступные варианты: ';
                FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
                    v_notation_str := idx_to_notation(v_all_legal_moves(i).path(1).start_idx, v_board_size);
                    FOR j IN 1 .. v_all_legal_moves(i).path.COUNT LOOP
                        v_notation_str := v_notation_str || CASE v_all_legal_moves(i).is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                                          || idx_to_notation(v_all_legal_moves(i).path(j).end_idx, v_board_size);
                    END LOOP;
                    
                    IF LENGTH(v_error_msg || v_notation_str || ' ') <= 2000 THEN
                        v_error_msg := v_error_msg || v_notation_str || ' ';
                    ELSE
                        v_error_msg := v_error_msg || '...';
                        EXIT;
                    END IF;
                END LOOP;
                v_error_msg := RTRIM(v_error_msg);
            END;
        ELSE
            v_error_msg := 'Нелегальный ход: "' || p_move_notation || '".';
        END IF;

        -- [ИСПРАВЛЕНИЕ ВЫЗОВА P_AUDIT_LOG]
        -- Передаем параметры явно и обрезаем сообщение до 255
        p_audit_log(
            p_player_id => p_player_id, 
            p_game_id   => p_game_id, 
            p_event_msg => SUBSTR(v_error_msg, 1, 255)
        );
        
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        p_status_message := v_error_msg;
        ROLLBACK;
        RETURN;
    END IF;

    -- Применение хода
    v_new_board_decoded := v_decoded_board;
    DECLARE
        v_moving_piece CHAR(1) := SUBSTR(v_new_board_decoded, v_chosen_move.path(1).start_idx, 1);
        v_start_pos    PLS_INTEGER := v_chosen_move.path(1).start_idx;
        v_end_pos      PLS_INTEGER := v_chosen_move.path(v_chosen_move.path.LAST).end_idx;
    BEGIN
        v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_start_pos + 1);
        
        IF v_chosen_move.is_capture = 'Y' THEN
            FOR i IN 1 .. v_chosen_move.path.COUNT LOOP
                v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_chosen_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_chosen_move.path(i).captured_idx + 1);
            END LOOP;
        END IF;
        
        IF v_moving_piece IN (c_white_man, c_black_man) THEN
            DECLARE
                v_end_row PLS_INTEGER := g_map_by_idx(v_end_pos).row_num;
                v_is_final_square_promotion BOOLEAN := (v_player_color = 'W' AND v_end_row = v_board_size) OR (v_player_color = 'B' AND v_end_row = 1);
            BEGIN
                IF v_is_final_square_promotion THEN
                    v_moving_piece := CASE v_player_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                END IF;
            END;
        END IF;
        v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board_decoded, v_end_pos + 1);
    END;

    v_new_board_encoded := encode_board(v_new_board_decoded);
    SELECT COUNT(*) + 1 INTO v_move_count FROM game_moves WHERE game_id = p_game_id;

    -- Определяем очередь хода ПОСЛЕ этого хода
    DECLARE
        v_next_turn CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
    BEGIN
        UPDATE games
        SET current_turn          = v_next_turn,
            draw_offer_status     = NULL, 
            draw_offered_by_color = NULL, 
            draw_offered_at       = NULL
        WHERE game_id = p_game_id;

        -- Сохраняем ход с позицией (очередь хода вычисляется по move_number: нечетные = белые, четные = черные)
        INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
        VALUES (p_game_id, v_move_count, p_move_notation, v_chosen_move.is_capture, v_new_board_encoded);
    END;
    
    -- Переносим таймаут хода на следующий ход
    BEGIN
        p_reschedule_move_timeout_job(p_game_id);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
    
    IF p_player_id IS NULL THEN
        p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
    ELSE
        p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
    END IF;

    -- Проверка окончания
    DECLARE
        v_next_turn_color       CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
        v_next_player_moves     t_move_list;
        v_opponent_pieces_exist BOOLEAN := FALSE;
        v_repetition_count      NUMBER;
    BEGIN
        IF v_next_turn_color = 'W' THEN
            IF INSTR(v_new_board_decoded, c_white_man) > 0 OR INSTR(v_new_board_decoded, c_white_king) > 0 THEN
                v_opponent_pieces_exist := TRUE;
            END IF;
        ELSE
            IF INSTR(v_new_board_decoded, c_black_man) > 0 OR INSTR(v_new_board_decoded, c_black_king) > 0 THEN
                v_opponent_pieces_exist := TRUE;
            END IF;
        END IF;
        
        IF NOT v_opponent_pieces_exist THEN
            p_drop_move_timeout_job(p_game_id);
            
            UPDATE games 
            SET status = 'V', 
                end_time = SYSDATE, 
                winner_player_color = v_player_color,
                puzzle_status = CASE WHEN puzzle_id IS NOT NULL THEN 's' ELSE puzzle_status END
            WHERE game_id = p_game_id;
            
            p_status_message := p_status_message || ' Победа! У противника не осталось фигур.';
            
            UPDATE spectators SET left_at = SYSDATE WHERE game_id = p_game_id AND left_at IS NULL;
            
            p_audit_log(p_player_id, p_game_id, 'WIN_NO_PIECES');
            p_update_ratings(p_game_id);
            COMMIT;
            RETURN;
        END IF;

        v_next_player_moves := find_all_player_moves(v_new_board_decoded, v_next_turn_color, v_game.rule_id);
        IF v_next_player_moves.COUNT = 0 THEN
            p_drop_move_timeout_job(p_game_id);
            
            UPDATE games 
            SET status = 'V', 
                end_time = SYSDATE, 
                winner_player_color = v_player_color,
                puzzle_status = CASE WHEN puzzle_id IS NOT NULL THEN 's' ELSE puzzle_status END
            WHERE game_id = p_game_id;
            
            p_status_message := p_status_message || ' Победа! Противник заблокирован.';

            UPDATE spectators SET left_at = SYSDATE WHERE game_id = p_game_id AND left_at IS NULL;
            
            p_audit_log(p_player_id, p_game_id, 'WIN_PAT');
            p_update_ratings(p_game_id);
            COMMIT;
            RETURN;
        END IF;

        -- Проверка "Ничья по N ходов без взятия"
        IF v_game.draw_moves_limit IS NOT NULL THEN
            DECLARE
                v_moves_without_capture PLS_INTEGER := 0;
                v_last_capture_move PLS_INTEGER;
            BEGIN
                -- Находим номер последнего хода с взятием
                BEGIN
                    SELECT MAX(move_number) INTO v_last_capture_move
                    FROM game_moves
                    WHERE game_id = p_game_id AND is_capture = 'Y';
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_last_capture_move := 0;
                END;
                
                -- Считаем ходы без взятия после последнего взятия (включая текущий ход)
                SELECT COUNT(*) INTO v_moves_without_capture
                FROM game_moves
                WHERE game_id = p_game_id
                  AND move_number > v_last_capture_move
                  AND is_capture = 'N';
                
                -- Добавляем текущий ход если он без взятия
                IF v_chosen_move.is_capture = 'N' THEN
                    v_moves_without_capture := v_moves_without_capture + 1;
                END IF;
                
                -- Проверяем лимит (draw_moves_limit - это количество полуходов без взятия)
                IF v_moves_without_capture >= v_game.draw_moves_limit THEN
                    p_drop_move_timeout_job(p_game_id);
                    
                    UPDATE games SET status = 'D', end_time = SYSDATE WHERE game_id = p_game_id;
                    p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия (' || v_game.draw_moves_limit || ').';
                    UPDATE spectators SET left_at = SYSDATE WHERE game_id = p_game_id AND left_at IS NULL;
                    p_audit_log(NULL, p_game_id, 'DRAW_MOVES_LIMIT');
                    p_update_ratings(p_game_id);
                    COMMIT;
                    RETURN;
                END IF;
            END;
        END IF;

        IF v_game.enable_pos_repetition_draw = 'Y' THEN
            -- Проверяем повтор позиции с учетом очереди хода
            -- Очередь хода ПОСЛЕ хода вычисляется по move_number:
            -- нечетные ходы (1,3,5...) -> после хода очередь черных (B)
            -- четные ходы (2,4,6...) -> после хода очередь белых (W)
            DECLARE
                v_next_turn_after_move CHAR(1) := CASE WHEN MOD(v_move_count, 2) = 1 THEN 'B' ELSE 'W' END;
            BEGIN
                SELECT COUNT(*) INTO v_repetition_count 
                FROM game_moves 
                WHERE game_id = p_game_id 
                  AND board_position = v_new_board_encoded
                  AND CASE WHEN MOD(move_number, 2) = 1 THEN 'B' ELSE 'W' END = v_next_turn_after_move;
                  
                IF v_repetition_count >= 2 THEN
                    p_drop_move_timeout_job(p_game_id);
                    
                    UPDATE games SET status = 'D', end_time = SYSDATE WHERE game_id = p_game_id;
                    p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.';
                    UPDATE spectators SET left_at = SYSDATE WHERE game_id = p_game_id AND left_at IS NULL;
                    p_audit_log(NULL, p_game_id, 'DRAW_REPETITION');
                    p_update_ratings(p_game_id);
                    COMMIT;
                    RETURN;
                END IF;
            END;
        END IF;
    END;
    
    COMMIT;
END p_process_move;
-- @procedure p_create_move_timeout_job
-- @brief Creates a scheduler job to timeout a move if time limit is exceeded
PROCEDURE p_create_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128);
    v_time_limit NUMBER;
BEGIN
    -- Получаем лимит времени на ход
    SELECT time_limit_move_sec INTO v_time_limit
    FROM games
    WHERE game_id = p_game_id;
    
    -- Если лимита нет, джоб не нужен
    IF v_time_limit IS NULL THEN
        RETURN;
    END IF;
    
    v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;
    
    -- Удаляем старый джоб если есть
    BEGIN
        DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
    
    -- Создаем новый джоб
    DBMS_SCHEDULER.CREATE_JOB(
        job_name   => v_job_name,
        job_type   => 'PLSQL_BLOCK',
        job_action => 'DECLARE
                v_game games%ROWTYPE;
                v_loser_color CHAR(1);
            BEGIN
                SELECT * INTO v_game FROM games WHERE game_id = ' || p_game_id || ' FOR UPDATE;
                
                -- Проверяем что игра еще активна
                IF v_game.status = ''A'' THEN
                    -- Проигравший - тот, чей сейчас ход
                    v_loser_color := v_game.current_turn;
                    
                    UPDATE games
                    SET status = ''T'', -- Timeout
                        end_time = SYSDATE,
                        winner_player_color = CASE v_loser_color WHEN ''W'' THEN ''B'' ELSE ''W'' END
                    WHERE game_id = ' || p_game_id || ';
                    
                    UPDATE spectators SET left_at = SYSDATE 
                    WHERE game_id = ' || p_game_id || ' AND left_at IS NULL;
                    
                    C##CHECKERS_APP.game_logic.p_update_ratings(' || p_game_id || ');
                    C##CHECKERS_APP.game_logic.p_audit_log(NULL, ' || p_game_id || ', ''MOVE_TIMEOUT'');
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;',
        start_date => SYSTIMESTAMP + (v_time_limit / 86400), -- Через time_limit_move_sec секунд
        enabled    => TRUE,
        auto_drop  => TRUE,
        comments   => 'Move timeout job for game ' || p_game_id
    );
EXCEPTION
    WHEN OTHERS THEN NULL; -- Игнорируем ошибки создания джоба
END p_create_move_timeout_job;
-- @procedure p_reschedule_move_timeout_job
-- @brief Reschedules the move timeout job when a move is made
PROCEDURE p_reschedule_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128);
    v_time_limit NUMBER;
BEGIN
    -- Получаем лимит времени на ход
    SELECT time_limit_move_sec INTO v_time_limit
    FROM games
    WHERE game_id = p_game_id;
    
    -- Если лимита нет, джоб не нужен
    IF v_time_limit IS NULL THEN
        RETURN;
    END IF;
    
    v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;
    
    -- Переносим время выполнения джоба
    BEGIN
        DBMS_SCHEDULER.SET_ATTRIBUTE(
            name      => v_job_name,
            attribute => 'start_date',
            value     => SYSTIMESTAMP + (v_time_limit / 86400)
        );
    EXCEPTION
        WHEN OTHERS THEN NULL; -- Если джоба нет, создаем его
            p_create_move_timeout_job(p_game_id);
    END;
EXCEPTION
    WHEN OTHERS THEN NULL;
END p_reschedule_move_timeout_job;
-- @procedure p_drop_move_timeout_job
-- @brief Drops the move timeout job when game ends
PROCEDURE p_drop_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
BEGIN
    BEGIN
        DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
END p_drop_move_timeout_job;
-- @procedure create_game
-- @brief Creates a new game (PvP, PvE, or puzzle).
-- @dependencies:
--   - players (table)
--   - games (table)
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - encode_board (function)
--   - get_initial_position (function)
--   - get_ai_move (function)
--   - p_process_move (procedure)
--   - print_active_board (procedure)

PROCEDURE create_game(
    p_opponent_username   IN VARCHAR2 DEFAULT NULL,
    p_ai_difficulty       IN CHAR     DEFAULT NULL,
    p_player_color        IN CHAR     DEFAULT NULL,
    p_rule_id             IN NUMBER   DEFAULT 1,
    p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
    p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
    p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
    p_enable_pos_rep_draw IN CHAR     DEFAULT 'N',
    p_puzzle_id           IN NUMBER   DEFAULT NULL,
    p_daily               IN CHAR     DEFAULT 'N'
) IS
    v_current_username    players.username%TYPE := USER;
    v_current_player_id   players.player_id%TYPE;
    v_opponent_player_id  players.player_id%TYPE;
    v_white_player_id     players.player_id%TYPE;
    v_black_player_id     players.player_id%TYPE;
    v_creator_color       CHAR(1);
    v_initial_position    VARCHAR2(128); -- Было games.board_position%TYPE, явно задаем 128
    v_encoded_position    VARCHAR2(128);
    v_status              games.status%TYPE;
    v_ai_move             VARCHAR2(50);
    v_ai_msg              VARCHAR2(1000);
    v_game_id             NUMBER;
    v_status_message      VARCHAR2(1000);
    v_my_active_game_id   NUMBER;
    v_error_msg           VARCHAR2(255);
BEGIN
    v_current_player_id := get_or_create_player_id(v_current_username);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_current_player_id;

    v_my_active_game_id := get_active_game(v_current_player_id);
    IF v_my_active_game_id IS NOT NULL THEN
        v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id;
        p_audit_log(v_current_player_id, v_my_active_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    -- Валидация параметров
    IF p_time_limit_move_sec IS NOT NULL AND p_time_limit_move_sec <= 0 THEN
        v_error_msg := 'Лимит времени на ход должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_time_limit_game_sec IS NOT NULL AND p_time_limit_game_sec <= 0 THEN
        v_error_msg := 'Лимит времени на партию должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_draw_moves_limit IS NOT NULL AND p_draw_moves_limit <= 0 THEN
        v_error_msg := 'Лимит ходов без взятий должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_enable_pos_rep_draw IS NOT NULL AND p_enable_pos_rep_draw NOT IN ('Y', 'N') THEN
        v_error_msg := 'Параметр enable_pos_rep_draw должен быть Y или N.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_player_color IS NOT NULL AND p_player_color NOT IN ('W', 'B') THEN
        v_error_msg := 'Цвет игрока должен быть W (белые) или B (черные).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (p_opponent_username IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_opponent_username IS NOT NULL)
    THEN
        v_error_msg := 'Конфликт параметров. Нельзя одновременно создавать Задачу, PVE и PVP.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    -- 1. Режим ЗАДАЧИ (Puzzle)
    IF p_puzzle_id IS NOT NULL THEN
        DECLARE
            v_puzzle puzzles%ROWTYPE;
        BEGIN
            SELECT * INTO v_puzzle FROM puzzles WHERE puzzle_id = p_puzzle_id;
            v_initial_position := v_puzzle.board_position;
            v_encoded_position := encode_board(v_initial_position);
            v_status := 'A';
            
            -- В задаче игрок всегда играет за сторону, чей ход (turn_to_move)
            IF v_puzzle.turn_to_move = 'W' THEN
                v_white_player_id := v_current_player_id;
                v_black_player_id := NULL;
                v_creator_color   := 'W';
            ELSE
                v_white_player_id := NULL;
                v_black_player_id := v_current_player_id;
                v_creator_color   := 'B';
            END IF;

            INSERT INTO games (
                rule_id, player_white_id, player_black_id, 
                creator_player_color,
                status, current_turn,
                puzzle_id, is_daily_puzzle, puzzle_status
            )
            VALUES (
                v_puzzle.rule_id, v_white_player_id, v_black_player_id, 
                v_creator_color,
                v_status, v_puzzle.turn_to_move,
                p_puzzle_id, p_daily, 'p' -- 'p' = pending
            )
            RETURNING game_id INTO v_game_id;
            
            v_status_message := 'Вы начали задачу ID ' || p_puzzle_id || '. (ID сессии: ' || v_game_id || ').';
            p_audit_log(v_current_player_id, v_game_id, 'START_PUZZLE');
        
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Задача с ID ' || p_puzzle_id || ' не найдена.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
    -- 2. Режим ИГРЫ (PvP / PvE)
    ELSIF p_puzzle_id IS NULL THEN
    
        DECLARE
            v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
        BEGIN
            v_creator_color := v_color_choice;
            IF v_color_choice = 'W' THEN
                v_white_player_id := v_current_player_id;
            ELSE
                v_black_player_id := v_current_player_id;
            END IF;
        END;

        v_initial_position := get_initial_position(p_rule_id);
        IF v_initial_position IS NULL THEN
            RETURN;
        END IF;
        v_encoded_position := encode_board(v_initial_position);

        -- 2.1. PvE (Игра с ИИ)
        IF p_ai_difficulty IS NOT NULL THEN
            v_status := 'A';
            -- Если игрок выбрал белых, слот черных NULL (для ИИ), и наоборот
            IF v_white_player_id IS NULL THEN v_white_player_id := NULL; ELSE v_black_player_id := NULL; END IF;

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                p_ai_difficulty, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Игра против ИИ создана (ID: ' || v_game_id || '). Вы играете за ' || CASE WHEN v_white_player_id = v_current_player_id THEN 'белых (W)' ELSE 'черных (B)' END || '.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_PVE_GAME');

            -- Если ИИ играет за белых (игрок выбрал черных или так выпало), ИИ делает первый ход
            IF v_white_player_id IS NULL THEN
                v_ai_move := get_ai_move(v_encoded_position, 'W', p_rule_id, p_ai_difficulty);
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                    v_status_message := v_status_message || ' ИИ начинает с хода: ' || v_ai_move;
                END IF;
            END IF;
        
        -- 2.2. PvP (Игра с человеком)
        ELSIF p_opponent_username IS NOT NULL THEN
            IF v_current_username = UPPER(p_opponent_username) THEN 
                v_error_msg := 'Нельзя вызвать самого себя.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

            DECLARE
                v_opp_active_game NUMBER := get_active_game(v_opponent_player_id);
            BEGIN
                IF v_opp_active_game IS NOT NULL THEN
                    v_error_msg := 'Игрок "' || p_opponent_username || '" уже занят в другой партии (ID: '|| v_opp_active_game ||').';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
            END;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
            v_status := 'C'; -- Challenged

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_CHALLENGE');
            
        -- 2.3. Открытая игра (Open Game)
        ELSE
            v_status := 'O';
            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_OPEN_GAME');
        END IF;
        
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(v_status_message);
    
    -- Если игра активна сразу (PvE / Puzzle), показываем доску
    IF (p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL) OR (p_puzzle_id IS NOT NULL) THEN
         BEGIN
            print_active_board(
                p_game_id => v_game_id,
                p_username => NULL,
                p_wait_for_turn => 'N'
            );
         EXCEPTION
            WHEN OTHERS THEN NULL;
         END;
     END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_game: ' || SQLERRM);
        RAISE;
END create_game;
-- @procedure join_game
-- @brief Allows a player to join an open or challenged game.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

PROCEDURE join_game(p_game_id IN NUMBER) IS
    v_game             games%ROWTYPE;
    v_player_id        players.player_id%TYPE;
    v_active_game_id   NUMBER;
    v_error_msg        VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    -- Логика для ПРЯМОГО ВЫЗОВА (Challenged)
    IF v_game.status = 'C' THEN
        DECLARE
            v_creator_id players.player_id%TYPE;
        BEGIN
            IF v_game.creator_player_color = 'W' THEN
                v_creator_id := v_game.player_white_id;
            ELSE
                v_creator_id := v_game.player_black_id;
            END IF;
            
            -- Проверка: Игрок должен быть в слоте оппонента и не быть создателем
            IF NOT (v_player_id IN (v_game.player_white_id, v_game.player_black_id) AND v_player_id != v_creator_id) THEN
                v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK; 
                RETURN;
            END IF;
            
            -- Для вызова разрешаем присоединение даже если get_active_game находит эту игру
            -- (потому что игрок уже в игре, но статус 'C' - он должен "принять" вызов)
        END;
        
    -- Логика для ОТКРЫТОЙ ИГРЫ (Open)
    ELSIF v_game.status = 'O' THEN
        -- Нельзя присоединиться к своей же игре
        IF v_player_id = v_game.player_white_id OR v_player_id = v_game.player_black_id THEN
            v_error_msg := 'Нельзя присоединиться к собственной открытой игре (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        -- Для открытой игры проверяем, не занят ли игрок в другой игре
        v_active_game_id := get_active_game(v_player_id);
        IF v_active_game_id IS NOT NULL AND v_active_game_id != p_game_id THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
    ELSE
        v_error_msg := 'Нельзя присоединиться к этой игре (ID: ' || p_game_id || ', статус: '|| v_game.status || ').';
        p_audit_log(v_player_id, p_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
    
    -- Обновление статуса игры
    IF v_game.status = 'O' THEN
        UPDATE games
        SET player_white_id = NVL(v_game.player_white_id, v_player_id),
            player_black_id = NVL(v_game.player_black_id, v_player_id),
            status          = 'A',
            start_time      = SYSDATE
        WHERE game_id = p_game_id;
    ELSE -- 'C'
        UPDATE games
        SET status     = 'A',
            start_time = SYSDATE
        WHERE game_id = p_game_id;
    END IF;
    
    -- Создаем джоб таймаута хода если есть лимит времени
    BEGIN
        p_create_move_timeout_job(p_game_id);
    EXCEPTION
        WHEN OTHERS THEN NULL; -- Игнорируем ошибки создания джоба
    END;
    
    p_audit_log(v_player_id, p_game_id, 'JOIN_GAME');
    DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при присоединении к игре: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 255));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END join_game;
-- @procedure resign_game
-- @brief Allows a player to resign from an active game.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - spectators (table)
--   - matches (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - p_update_ratings (procedure)

PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N') IS
    v_game        games%ROWTYPE;
    v_player_id   players.player_id%TYPE;
    v_game_id     NUMBER;
    v_error_msg   VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(user);
    
    -- Проверка: Нельзя сдаться, если ты зритель
    DECLARE
        v_spectating_game_id NUMBER;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_spectating_game_id := NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя сдаться.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;
    
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
    v_game_id   := get_active_game(v_player_id);

    IF v_game_id IS NULL THEN
        v_error_msg := 'У вас нет активной партии, чтобы сдаться.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status NOT IN ('A') THEN
        v_error_msg := 'Эта партия (ID: ' || v_game_id || ') неактивна (статус '||v_game.status||'). Используйте cancel_game для отмены вызова.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    -- 1. Сдача в режиме ПАЗЛА
    IF v_game.puzzle_id IS NOT NULL THEN
        p_drop_move_timeout_job(v_game_id);
        
        UPDATE games
        SET status = 'V',
            end_time = SYSDATE,
            puzzle_status = 'f' -- Failed
        WHERE game_id = v_game_id;
        
        UPDATE spectators SET left_at = SYSDATE 
        WHERE game_id = v_game_id AND left_at IS NULL;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'QUIT_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('[OK] Вы вышли из попытки решения задачи (ID сессии: ' || v_game_id || ').');
        
    -- 2. Сдача в режиме ИГРЫ
    ELSE
        DECLARE
            v_winner_id       players.player_id%TYPE;
            v_winner_color    CHAR(1);
            v_winner_username players.username%TYPE;
        BEGIN
            IF v_player_id = v_game.player_white_id THEN
                v_winner_id := v_game.player_black_id;
                v_winner_color := 'B';
            ELSE
                v_winner_id := v_game.player_white_id;
                v_winner_color := 'W';
            END IF;

            p_drop_move_timeout_job(v_game_id);
            
            UPDATE games
            SET status              = 'R', -- Resigned
                winner_player_color = v_winner_color,
                end_time            = SYSDATE
            WHERE game_id = v_game_id;

            UPDATE spectators SET left_at = SYSDATE 
            WHERE game_id = v_game_id AND left_at IS NULL;

            -- Сдача во всем МАТЧЕ
            IF UPPER(p_resign_match) = 'Y' AND v_game.match_id IS NOT NULL THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_winner_id
                WHERE match_id = v_game.match_id;
                
                p_audit_log(v_player_id, v_game.game_id, p_event_msg => 'MATCH_RESIGN');
                DBMS_OUTPUT.PUT_LINE('Вы также сдались во всем матче (ID: ' || v_game.match_id || ').');
            END IF;

            IF v_winner_id IS NOT NULL THEN
                SELECT username INTO v_winner_username FROM players WHERE player_id = v_winner_id;
            ELSE
                v_winner_username := 'AI (Server)';
            END IF;
            
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'RESIGN_GAME');
            p_update_ratings(v_game_id); 
            DBMS_OUTPUT.PUT_LINE('[OK] Вы сдались в партии ' || v_game_id || '. Победитель: ' || v_winner_username || '.');
        END;
    END IF;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END resign_game;
-- @procedure watch_game_replay
-- @brief Allows a player to watch a replay of a finished game.
-- @dependencies:
--   - players (table)
--   - games (table)
--   - game_moves (table)
--   - v_game_protocol (view)
--   - get_or_create_player_id (function)
--   - p_audit_log (procedure)
--   - f_get_board_as_clob (function)
--   - decode_board (function)

PROCEDURE watch_game_replay(
    p_game_id       IN NUMBER,
    p_moves_to_show IN NUMBER DEFAULT 1
) IS
    v_player_id      players.player_id%TYPE;
    v_seq_name       VARCHAR2(64);
    v_job_name       VARCHAR2(64);
    v_move_num       NUMBER;
    v_color_str      VARCHAR2(30);
    v_session_exists PLS_INTEGER;
    v_game_rec       games%ROWTYPE;
    v_max_moves      NUMBER;
    v_winner_name    players.username%TYPE;
    v_loser_name     players.username%TYPE;
    v_final_message  VARCHAR2(250);
    v_error_msg      VARCHAR2(255);
    v_replay_finished BOOLEAN := FALSE;
    v_replay_error    BOOLEAN := FALSE;
    
    CURSOR c_game_moves (cp_game_id NUMBER, cp_move_number NUMBER) IS
        SELECT
            username,
            player_color,
            move_notation,
            board_position
        FROM v_game_protocol
        WHERE game_id = cp_game_id AND move_number = cp_move_number;

BEGIN
    v_player_id := get_or_create_player_id(USER);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
    
    v_seq_name  := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id;
    v_job_name  := 'DROP_REPLAY_SEQ_' || p_game_id || '_' || v_player_id;

    -- 1. Проверка или инициализация сессии
    SELECT COUNT(*) INTO v_session_exists 
    FROM user_sequences 
    WHERE sequence_name = v_seq_name;

    IF v_session_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('--[ Создание новой сессии просмотра для игры ' || p_game_id || ' ]--');
        
        BEGIN
            SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
        IF v_game_rec.status IN ('A', 'O', 'C') THEN
            v_error_msg := 'Нельзя просматривать активную (или не начатую) партию (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        SELECT count(*) INTO v_max_moves FROM game_moves WHERE game_id = p_game_id;
        IF v_max_moves = 0 THEN
            v_error_msg := 'В этой партии (ID: ' || p_game_id || ') нет ходов для просмотра.';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- Удаляем старый джоб очистки, если он завис
        BEGIN DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;

        -- Создаем последовательность для навигации
        EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seq_name || 
                          ' START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE ' || 
                          v_max_moves || ' NOCYCLE NOCACHE';
        
        -- Создаем джоб для удаления последовательности через 30 мин (Garbage Collection)
        DBMS_SCHEDULER.create_job(
            job_name   => v_job_name,
            job_type   => 'PLSQL_BLOCK',
            job_action => 'BEGIN EXECUTE IMMEDIATE ''DROP SEQUENCE ' || v_seq_name || '''; END;',
            start_date => SYSTIMESTAMP + INTERVAL '30' MINUTE,
            enabled    => TRUE,
            auto_drop  => TRUE,
            comments   => 'Drop replay sequence for game ' || p_game_id || ' player ' || v_player_id
        );
        COMMIT;
        
    END IF;
    
    -- Если сессия уже была, загружаем данные игры для финализации
    IF v_game_rec.game_id IS NULL THEN
         SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
    END IF;

    -- 2. Вывод ходов
    FOR i IN 1 .. p_moves_to_show LOOP
        BEGIN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num;
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE = -8004 THEN -- MAXVALUE exceeded
                        v_replay_finished := TRUE;
                    ELSE
                        v_replay_error := TRUE;
                        v_error_msg := 'Ошибка сессии просмотра (ID: ' || p_game_id || '). ' || SQLERRM;
                        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 255));
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    END IF;
            END;

            IF v_replay_error THEN
                EXIT;
            END IF;

            IF v_replay_finished THEN
                -- Формирование финального сообщения
                BEGIN
                    IF v_game_rec.status = 'D' THEN
                        v_final_message := 'Ничья.';
                    ELSIF v_game_rec.status = 'T' THEN
                        v_final_message := 'Игра завершена по таймауту.';
                    ELSIF v_game_rec.status IN ('V', 'R') THEN 
                        DECLARE
                            v_winner_id players.player_id%TYPE;
                            v_loser_id  players.player_id%TYPE;
                        BEGIN
                            IF v_game_rec.winner_player_color = 'W' THEN
                                v_winner_id := v_game_rec.player_white_id;
                                v_loser_id  := v_game_rec.player_black_id;
                            ELSE
                                v_winner_id := v_game_rec.player_black_id;
                                v_loser_id  := v_game_rec.player_white_id;
                            END IF;
                            
                            BEGIN SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; EXCEPTION WHEN NO_DATA_FOUND THEN v_winner_name := 'AI'; END;
                            BEGIN SELECT username INTO v_loser_name  FROM players WHERE player_id = v_loser_id;  EXCEPTION WHEN NO_DATA_FOUND THEN v_loser_name  := 'AI'; END;

                            IF v_game_rec.status = 'R' THEN
                                v_final_message := v_loser_name || ' сдался. Победитель: ' || v_winner_name || '.';
                            ELSE
                                v_final_message := 'Победа игрока ' || v_winner_name || '.';
                            END IF;
                        END;
                    ELSE
                        v_final_message := 'Игра завершена (Статус: ' || v_game_rec.status || ').';
                    END IF;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_final_message := 'Игра не найдена.';
                END;
                
                DBMS_OUTPUT.PUT_LINE('--[ КОНЕЦ ПАРТИИ ]-- ' || v_final_message);
                EXIT;
            END IF;

            -- Печать хода
            FOR move_rec IN c_game_moves(p_game_id, v_move_num) LOOP
                v_color_str := CASE move_rec.player_color WHEN 'W' THEN '(Белые)' ELSE '(Черные)' END;
                DBMS_OUTPUT.PUT_LINE('---');
                DBMS_OUTPUT.PUT_LINE(
                    'Ход ' || v_move_num || ' ' || 
                    RPAD(NVL(move_rec.username, 'AI'), 20) || ' ' ||
                    RPAD(v_color_str, 10) || ' : ' || 
                    move_rec.move_notation
                );
                DBMS_OUTPUT.PUT_LINE(f_get_board_as_clob(decode_board(move_rec.board_position)));
            END LOOP;

        END;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Ошибка в watch_game_replay: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 255));
        RAISE;
END watch_game_replay;
-- @procedure stop_spectating
-- @brief Allows a player to stop spectating a game.
-- @dependencies:
--   - spectators (table)
--   - get_or_create_player_id (function)

PROCEDURE stop_spectating IS
    v_player_id players.player_id%TYPE;
    v_count     PLS_INTEGER;
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    UPDATE spectators
    SET left_at = SYSDATE
    WHERE player_id = v_player_id
      AND left_at IS NULL
    RETURNING COUNT(*) INTO v_count;
    
    COMMIT;
    
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Вы вышли из режима просмотра.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Вы не находились в режиме просмотра.');
    END IF;
    
END stop_spectating;
-- @procedure print_active_board
-- @brief Prints the active board of a game, with optional highlighting and waiting for the player's turn.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - spectators (table)
--   - game_moves (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - decode_board (function)
--   - find_all_player_moves (function)
--   - f_get_board_as_clob (function)
--   - t_map_indices, t_move_list (types)

PROCEDURE print_active_board(
    p_game_id       IN NUMBER   DEFAULT NULL,
    p_username      IN VARCHAR2 DEFAULT NULL,
    p_wait_for_turn IN CHAR     DEFAULT 'N'
) IS
    v_target_game_id   games.game_id%TYPE;
    v_target_user_id   players.player_id%TYPE;
    v_target_username  players.username%TYPE;
    v_game             games%ROWTYPE;
    v_printable_board  CLOB;
    v_status_header    VARCHAR2(200);
    v_player_username  players.username%TYPE;
    v_move_count       NUMBER;
    c_nl CONSTANT      VARCHAR2(1) := CHR(10);
    v_error_msg        VARCHAR2(255);
    v_viewer_player_id players.player_id%TYPE;
    
    v_my_color         CHAR(1);
    v_loop_start_time  DATE;
    v_timeout_sec      NUMBER;
    v_wait_message     VARCHAR2(200);
    
    -- Для логики отрисовки
    v_board_size       PLS_INTEGER;

BEGIN
    v_viewer_player_id := get_or_create_player_id(USER);
    
    IF p_game_id IS NOT NULL AND p_username IS NOT NULL THEN
        v_error_msg := 'Для поиска передайте процедуре только один параметр (имя пользователя или id игры).';
        p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    ELSIF p_game_id IS NOT NULL THEN
        v_target_game_id := p_game_id;
    ELSIF p_username IS NOT NULL THEN
        v_target_username := UPPER(p_username);
        BEGIN
            SELECT player_id INTO v_target_user_id FROM players WHERE username = v_target_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Пользователя "' || p_username || '" не существует.';
                p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        v_target_game_id := get_active_game(v_target_user_id);
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У пользователя "' || p_username || '" не найдено активных сессий.';
            p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    ELSE
        v_target_user_id := v_viewer_player_id; 
        v_target_game_id := get_active_game(v_target_user_id); 
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У вас нет активных игр.';
            p_audit_log(v_target_user_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    END IF;
    
    -- Завершаем другие просмотры
    UPDATE spectators
    SET left_at = SYSDATE
    WHERE player_id = v_viewer_player_id
      AND left_at IS NULL
      AND game_id != v_target_game_id;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;
    
    -- Вход зрителя
    IF v_viewer_player_id NOT IN (v_game.player_white_id, v_game.player_black_id)
       AND v_game.status IN ('A', 'O', 'C')
    THEN
        MERGE INTO spectators s
        USING (SELECT v_viewer_player_id AS player_id, v_target_game_id AS game_id FROM DUAL) d
        ON (s.player_id = d.player_id AND s.game_id = d.game_id AND s.left_at IS NULL)
        WHEN NOT MATCHED THEN
            INSERT (player_id, game_id, joined_at)
            VALUES (d.player_id, d.game_id, SYSDATE);
        
        p_audit_log(v_viewer_player_id, v_target_game_id, 'SPECTATOR_JOIN');
        DBMS_OUTPUT.PUT_LINE('--[ Вы вошли в режим просмотра (ID: ' || v_target_game_id || ') ]--');
    END IF;
    
    COMMIT;

    -- Определение цвета игрока (если это участник)
    DECLARE
        v_active_player_id  players.player_id%TYPE;
        v_highlight_indices t_map_indices;
        v_legal_moves       t_move_list;
        v_decoded_board     VARCHAR2(128); -- Было 200
    BEGIN
        IF v_game.player_white_id = v_viewer_player_id THEN
            v_my_color := 'W';
        ELSIF v_game.player_black_id = v_viewer_player_id THEN
            v_my_color := 'B';
        ELSE
            v_my_color := NULL; 
        END IF;

        -- Логика ожидания хода
        IF UPPER(p_wait_for_turn) = 'Y' 
        AND v_my_color IS NOT NULL
        AND v_game.current_turn != v_my_color
        AND v_game.status = 'A'
        THEN
            v_loop_start_time := SYSDATE;
            v_timeout_sec := NVL(v_game.time_limit_move_sec, 300); 

            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE('Ожидание вашего хода... (Тайм-аут: ' || v_timeout_sec || ' сек)');
            
            WHILE v_game.current_turn != v_my_color 
            AND v_game.status = 'A' 
            AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400) 
            LOOP
                dbms_session.sleep(3); 
                SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
            END LOOP;
            
            IF v_game.current_turn = v_my_color THEN
                v_wait_message := 'ВАШ ХОД!';
            ELSIF v_game.status != 'A' THEN
                v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
            ELSE 
                v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
            END IF;
        END IF;
        
        -- Если игра закончилась пока ждали
        IF v_game.status NOT IN ('A', 'O', 'C') THEN
            v_error_msg := 'Игра с id = ' || v_target_game_id || ' закончена. (Статус: ' || v_game.status || ')';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('-- Используйте watch_game_replay(' || v_target_game_id || ') для просмотра.');
            
            UPDATE spectators SET left_at = SYSDATE 
            WHERE player_id = v_viewer_player_id AND game_id = v_target_game_id AND left_at IS NULL;
            COMMIT;
            
            RETURN;
        END IF;

        -- Получаем текущую позицию доски: из последнего хода или начальная позиция
        BEGIN
            SELECT decode_board(board_position) INTO v_decoded_board
            FROM game_moves
            WHERE game_id = v_target_game_id
            ORDER BY move_number DESC
            FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Если ходов нет, используем начальную позицию
                v_decoded_board := get_initial_position(v_game.rule_id);
                IF v_decoded_board IS NULL THEN
                    v_error_msg := 'Критическая ошибка: Не удалось получить начальную позицию.';
                    p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
        END;
        
        -- [ВАЖНО] Инициализируем карту для корректной работы подсветки ходов
        v_board_size := SQRT(LENGTH(v_decoded_board));
        p_init_board_map(v_board_size);

        v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
        
        -- Подсветка возможных ходов (только для активного игрока)
        BEGIN
            IF v_game.status = 'A' AND v_viewer_player_id = v_active_player_id THEN
                v_legal_moves := find_all_player_moves(v_decoded_board, v_game.current_turn, v_game.rule_id);
                IF v_legal_moves.COUNT > 0 AND v_legal_moves(1).is_capture = 'Y' THEN
                    FOR i IN 1 .. v_legal_moves.COUNT LOOP
                        FOR j IN 1 .. v_legal_moves(i).path.COUNT LOOP
                            v_highlight_indices(v_legal_moves(i).path(j).end_idx) := TRUE;
                        END LOOP;
                    END LOOP;
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL; -- Игнорируем ошибки подсветки
        END;
        
        IF v_wait_message IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE(v_wait_message);
        END IF;

        IF v_game.status = 'A' THEN
            SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
            IF v_active_player_id IS NOT NULL THEN
                SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
            END IF;
            v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
        ELSE 
            v_status_header := 'Состояние доски: ' || v_game.status || '. Ожидание игрока.';
        END IF;
        DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);

        v_printable_board := f_get_board_as_clob(v_decoded_board, v_highlight_indices);
        DBMS_OUTPUT.PUT_LINE(v_printable_board);
    END;
END print_active_board;
-- @procedure make_move
-- @brief Makes a move in the current game.
-- @dependencies:
--   - players (table)
--   - games (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - p_process_move (procedure)
--   - print_active_board (procedure)
--   - get_ai_move (function)

PROCEDURE make_move(p_move_notation IN VARCHAR2) IS
    v_game_id   NUMBER;
    v_game      games%ROWTYPE;
    v_player_id players.player_id%TYPE;
    v_human_msg VARCHAR2(2000);
    v_ai_msg    VARCHAR2(2000);
    c_nl CONSTANT VARCHAR2(1) := CHR(10);
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    v_game_id   := get_active_game(v_player_id);
    
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id; 
    
    IF v_game_id IS NULL THEN
        v_error_msg := 'Нет активных игр, чтобы сделать ход.';
        p_audit_log(v_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    -- Блокируем строку для обновления (улучшение конкурентности)
    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status <> 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') еще не активна. Противник не подключился.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (v_game.current_turn = 'W' AND v_game.player_white_id != v_player_id) OR 
       (v_game.current_turn = 'B' AND v_game.player_black_id != v_player_id) 
    THEN
        v_error_msg := 'Сейчас не ваш ход. (ID Игры: ' || v_game_id || ', Очередь: ' || v_game.current_turn || ').';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    -- Ход человека
    p_process_move(v_game_id, p_move_notation, v_player_id, v_human_msg);
    
    -- Если ошибка, выходим (сообщение уже напечатано в p_process_move)
    IF INSTR(LOWER(v_human_msg), 'неверный ход') > 0 OR INSTR(LOWER(v_human_msg), 'нелегальный ход') > 0 THEN
        RETURN;
    END IF;
    
    -- Показываем доску после хода человека
    BEGIN
        print_active_board(p_game_id => v_game_id); 
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
    
    -- Ход ИИ (если нужно)
    DECLARE
        v_next_game_state games%ROWTYPE;
        v_ai_move         VARCHAR2(100);
        v_ai_board_pos    VARCHAR2(128);
    BEGIN
        SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;

        -- ИИ ходит, если игра активна и сейчас его очередь (слот игрока NULL)
        IF v_next_game_state.status = 'A' AND v_next_game_state.ai_difficulty IS NOT NULL AND
           ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id IS NULL) OR
            (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id IS NULL))
        THEN
            -- Получаем текущую позицию доски: из последнего хода или начальная позиция
            BEGIN
                SELECT board_position INTO v_ai_board_pos
                FROM game_moves
                WHERE game_id = v_game_id
                ORDER BY move_number DESC
                FETCH FIRST 1 ROW ONLY;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Если ходов нет, используем начальную позицию
                    v_ai_board_pos := get_initial_position(v_next_game_state.rule_id);
                    IF v_ai_board_pos IS NULL THEN
                        v_error_msg := 'Критическая ошибка: Не удалось получить начальную позицию для ИИ.';
                        p_audit_log(v_player_id, v_game_id, v_error_msg);
                        RETURN;
                    END IF;
                    -- Кодируем начальную позицию для передачи в get_ai_move
                    v_ai_board_pos := encode_board(v_ai_board_pos);
            END;
            
            v_ai_move := get_ai_move(
                p_board_position => v_ai_board_pos, 
                p_ai_color       => v_next_game_state.current_turn, 
                p_rule_id        => v_next_game_state.rule_id, 
                p_difficulty     => v_next_game_state.ai_difficulty
            );

            IF v_ai_move IS NOT NULL THEN
                p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                
                BEGIN
                    print_active_board(p_game_id => v_game_id);
                EXCEPTION
                    WHEN OTHERS THEN NULL;
                END;
            END IF;
        END IF;
    END;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END make_move;
-- @procedure cancel_game
-- @brief Cancels an open or challenged game.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

PROCEDURE cancel_game IS
    v_game_id   NUMBER;
    v_player_id players.player_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(user);
    
    -- Проверка на зрителя
    DECLARE
        v_spectating_game_id NUMBER;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_spectating_game_id := NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя отменить игру.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
    v_game_id := get_active_game(v_player_id);
    
    IF v_game_id IS NULL THEN
        v_error_msg := 'Нет активных игр или вызовов для отмены.';
        p_audit_log(v_player_id, NULL, v_error_msg); 
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
  
    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Эту игру (ID: ' || v_game_id || ') нельзя отменить (статус '||v_game.status||'). Используйте resign_game, чтобы сдаться.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
    
    -- Если это часть матча, отменяем и матч
    IF v_game.match_id IS NOT NULL THEN
        DELETE FROM matches WHERE match_id = v_game.match_id;
        p_audit_log(v_player_id, v_game_id, 'MATCH_CANCEL');
        DBMS_OUTPUT.PUT_LINE('Связанный вызов на матч (ID: ' || v_game.match_id || ') также отменен.');
    END IF;
            
    DELETE FROM games WHERE game_id = v_game_id;
    p_audit_log(v_player_id, v_game_id, 'CANCEL_GAME');
    DBMS_OUTPUT.PUT_LINE('Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при отмене игры: ' || SQLERRM;
        p_audit_log(v_player_id, v_game_id, SUBSTR(v_error_msg, 1, 255));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END cancel_game;
-- @procedure draw
-- @brief Manages draw offers (offer, accept, decline).
-- @dependencies:
--   - games (table)
--   - players (table)
--   - spectators (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - p_update_ratings (procedure)

PROCEDURE draw(p_action IN CHAR) IS
    v_player_id players.player_id%TYPE;
    v_game_id   games.game_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
    v_my_color  CHAR(1);
    v_action    CHAR(1) := UPPER(p_action);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    -- Проверка на зрителя
    DECLARE
        v_spectating_game_id NUMBER;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_spectating_game_id := NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя управлять ничьей.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    v_game_id := get_active_game(v_player_id);
    IF v_game_id IS NULL THEN
        v_error_msg := 'У вас нет активной игры.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN 
            v_error_msg := 'Активная игра ' || v_game_id || ' не найдена (возможно, баг).';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    IF v_game.status != 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') неактивна (статус: ' || v_game.status || ').';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.ai_difficulty IS NOT NULL THEN
        v_error_msg := 'Предложение ничьей недоступно в играх против ИИ.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.player_white_id = v_player_id THEN
        v_my_color := 'W';
    ELSE
        v_my_color := 'B';
    END IF;

    -- OFFER
    IF v_action = 'O' THEN
        IF v_game.draw_offer_status = 'O' THEN
            IF v_game.draw_offered_by_color = v_my_color THEN
                v_error_msg := 'Вы уже предложили ничью.';
            ELSE
                v_error_msg := 'Ваш оппонент уже предложил ничью. Вы можете ее принять (A) или отклонить (C).';
            END IF;
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET draw_offer_status     = 'O',
            draw_offered_by_color = v_my_color,
            draw_offered_at       = SYSDATE
        WHERE game_id = v_game_id;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_OFFER');
        DBMS_OUTPUT.PUT_LINE('Вы предложили ничью. Ожидайте ответа оппонента.');

    -- ACCEPT
    ELSIF v_action = 'A' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его принять.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        IF v_game.draw_offered_by_color = v_my_color THEN
            v_error_msg := 'Нельзя принять собственное предложение о ничьей.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        p_drop_move_timeout_job(v_game_id);
        
        UPDATE games
        SET status = 'D',
            end_time = SYSDATE,
            draw_offer_status = 'S'
        WHERE game_id = v_game_id;
        
        UPDATE spectators SET left_at = SYSDATE 
        WHERE game_id = v_game_id AND left_at IS NULL;

        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_ACCEPT');
        p_update_ratings(v_game_id); 
        DBMS_OUTPUT.PUT_LINE('Ничья по соглашению сторон.');

    -- CANCEL / DECLINE
    ELSIF v_action = 'C' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его отменить/отклонить.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET draw_offer_status     = NULL, 
            draw_offered_by_color = NULL,
            draw_offered_at       = NULL
        WHERE game_id = v_game_id;

        IF v_game.draw_offered_by_color = v_my_color THEN
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_CANCEL');
            DBMS_OUTPUT.PUT_LINE('Вы отменили свое предложение о ничьей.');
        ELSE
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_DECLINE');
            DBMS_OUTPUT.PUT_LINE('Вы отклонили предложение оппонента о ничьей.');
        END IF;

    ELSE
        v_error_msg := 'Неверный p_action: "' || p_action || '". Допустимые значения: O, A, C.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END draw;
-- @procedure create_match
-- @brief Creates a new match (a series of games).
-- @dependencies:
--   - players (table)
--   - matches (table)
--   - games (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - create_game (procedure)

PROCEDURE create_match(
    p_opponent_username   IN VARCHAR2,
    p_games_to_win        IN NUMBER,
    p_player_color        IN CHAR     DEFAULT NULL,
    p_rule_id             IN NUMBER   DEFAULT 1,
    p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
    p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
    p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
    p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'
) IS
    v_current_player_id  players.player_id%TYPE;
    v_error_msg          VARCHAR2(255);
    v_status_message     VARCHAR2(255);
    
    v_game_id            games.game_id%TYPE;
    v_match_id           matches.match_id%TYPE;
    
BEGIN
    v_current_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_current_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_current_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_games_to_win IS NULL OR p_games_to_win <= 0 THEN
        v_error_msg := 'Неверное количество игр для победы (p_games_to_win).';
        p_audit_log(v_current_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    -- Create the first game of the match
    create_game(
        p_opponent_username   => p_opponent_username,
        p_ai_difficulty       => NULL, -- Matches are PvP only
        p_player_color        => p_player_color,
        p_rule_id             => p_rule_id,
        p_time_limit_move_sec => p_time_limit_move_sec,
        p_time_limit_game_sec => p_time_limit_game_sec,
        p_draw_moves_limit    => p_draw_moves_limit,
        p_enable_pos_rep_draw => p_enable_pos_rep_draw,
        p_puzzle_id           => NULL,
        p_daily               => 'N'
    );
    
    v_game_id := get_active_game(v_current_player_id);
    
    -- If game creation failed (e.g., validation error in create_game), exit
    IF v_game_id IS NULL THEN
        RETURN;
    END IF;

    -- Create Match Record
    -- We split this into SELECT then INSERT to allow RETURNING clause
    DECLARE
        v_fetched_rule_id games.rule_id%TYPE;
        v_fetched_status  games.status%TYPE;
    BEGIN
        SELECT rule_id, status 
        INTO v_fetched_rule_id, v_fetched_status
        FROM games 
        WHERE game_id = v_game_id;

        INSERT INTO matches (
            rule_id, 
            games_to_win, 
            status
        )
        VALUES (
            v_fetched_rule_id,
            p_games_to_win,
            v_fetched_status
        )
        RETURNING match_id INTO v_match_id;
    END;

    -- Link Game to Match
    UPDATE games
    SET match_id = v_match_id
    WHERE game_id = v_game_id;
    
    IF p_opponent_username IS NOT NULL THEN
        v_status_message := 'Вызов на матч (ID: ' || v_match_id || ') до ' || p_games_to_win || ' побед брошен игроку ' || p_opponent_username;
    ELSE
        v_status_message := 'Открытый матч (ID: ' || v_match_id || ') до ' || p_games_to_win || ' побед создан. Ожидайте оппонента.';
    END IF;

    p_audit_log(v_current_player_id, v_game_id, 'MATCH_CREATED');
    DBMS_OUTPUT.PUT_LINE(v_status_message);
    
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_match: ' || SQLERRM);
        RAISE;
END create_match;
-- @procedure join_match
-- @brief Allows a player to join an open or challenged match.
-- @dependencies:
--   - players (table)
--   - matches (table)
--   - games (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - join_game (procedure)

PROCEDURE join_match(p_match_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_match     matches%ROWTYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    BEGIN
        SELECT * INTO v_match 
        FROM matches 
        WHERE match_id = p_match_id 
        FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Матч с ID ' || p_match_id || ' не найден.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    BEGIN
        SELECT * INTO v_game 
        FROM games 
        WHERE match_id = p_match_id 
          AND status IN ('O', 'C');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Не найдено ожидающей игры для этого матча (ID: ' || p_match_id || ').';
            p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
    END;
    
    IF v_match.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Матч (ID: ' || p_match_id || ') уже начат или завершен (Статус: ' || v_match.status || ').';
        p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
    
    -- Вызов join_game (она внутри сделает COMMIT при успехе)
    join_game(v_game.game_id);
    
    -- Проверяем, прошла ли операция успешно
    DECLARE
        v_game_status CHAR(1);
    BEGIN
        SELECT status INTO v_game_status 
        FROM games 
        WHERE game_id = v_game.game_id;
        
        IF v_game_status = 'A' THEN
            UPDATE matches
            SET status = 'A'
            WHERE match_id = p_match_id;
            
            DBMS_OUTPUT.PUT_LINE('Вы присоединились к матчу (ID: ' || p_match_id || '). Начинается первая игра (ID: ' || v_game.game_id || ').');
            p_audit_log(v_player_id, v_game.game_id, 'MATCH_JOINED');
            COMMIT;
        ELSE
            -- Если join_game не перевел игру в Active (ошибка), откатываем блокировку матча
            ROLLBACK;
        END IF;
    END;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END join_match;
-- @procedure create_puzzle
-- @brief Creates a new puzzle.
-- @dependencies:
--   - players (table)
--   - puzzles (table)
--   - game_rules (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - encode_board (function)

PROCEDURE create_puzzle(
    p_board_position   IN CLOB,
    p_turn_to_move     IN CHAR,
    p_moves_to_solve   IN NUMBER DEFAULT NULL,
    p_difficulty_level IN CHAR DEFAULT 'E'
) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(500);
    
    v_single_line_board VARCHAR2(200) := '';
    v_line              VARCHAR2(200);
    v_offset            NUMBER := 1;
    v_clob_len          NUMBER;
    v_line_break        NUMBER;
    c_nl                CHAR(1) := CHR(10);
    v_board_size        NUMBER;
    v_rule_id           game_rules.rule_id%TYPE;
    v_encoded_board     VARCHAR2(128); -- Было puzzles.board_position%TYPE
    v_new_puzzle_id     puzzles.puzzle_id%TYPE;

BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы создать задачу.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF UPPER(p_turn_to_move) NOT IN ('W', 'B') THEN
        v_error_msg := 'Ошибка: p_turn_to_move должен быть ''W'' или ''B''.';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_moves_to_solve IS NOT NULL AND p_moves_to_solve <= 0 THEN
         v_error_msg := 'Ошибка: p_moves_to_solve должен быть больше 0 или NULL.';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_difficulty_level IS NOT NULL AND p_difficulty_level NOT IN ('E', 'M', 'H') THEN
        v_error_msg := 'Ошибка: p_difficulty_level должен быть ''E'' (Easy), ''M'' (Medium) или ''H'' (Hard).';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        v_clob_len := DBMS_LOB.getlength(p_board_position);
        
        -- Парсинг CLOB построчно
        WHILE v_offset <= v_clob_len LOOP
            v_line_break := DBMS_LOB.instr(p_board_position, c_nl, v_offset);
            
            IF v_line_break = 0 THEN
                -- Читаем до конца (amount = len - offset + 1)
                v_line := DBMS_LOB.substr(p_board_position, v_clob_len - v_offset + 1, v_offset);
                v_offset := v_clob_len + 1;
            ELSE
                -- Читаем до переноса (amount = break - offset)
                v_line := DBMS_LOB.substr(p_board_position, v_line_break - v_offset, v_offset);
                v_offset := v_line_break + 1;
            END IF;
            
            -- Очистка от пробелов/табуляций/переносов (включая возможный \r)
            v_line := REGEXP_REPLACE(v_line, '[[:space:]]', '');
            
            IF LENGTH(v_line) > 0 THEN
                -- Защита от переполнения (если кто-то сунет гигантский CLOB)
                IF LENGTH(v_single_line_board) + LENGTH(v_line) > 200 THEN
                     v_error_msg := 'Ошибка: Размер доски превышает допустимый предел.';
                     RAISE_APPLICATION_ERROR(-20006, v_error_msg);
                END IF;
                v_single_line_board := v_single_line_board || v_line;
            END IF;
        END LOOP;

        IF LENGTH(v_single_line_board) = 64 THEN
            v_board_size := 8;
        ELSIF LENGTH(v_single_line_board) = 100 THEN
            v_board_size := 10;
        ELSE
            v_error_msg := 'Ошибка: Неверный размер доски. Ожидалось 64 (8x8) или 100 (10x10) символов, получено: ' || LENGTH(v_single_line_board);
            RAISE_APPLICATION_ERROR(-20001, v_error_msg);
        END IF;
        
        IF REGEXP_LIKE(v_single_line_board, '[^wWbB+]') THEN
            v_error_msg := 'Ошибка: Доска содержит недопустимые символы. Разрешены только: w, W, b, B, +.';
            RAISE_APPLICATION_ERROR(-20002, v_error_msg);
        END IF;
        
        IF INSTR(v_single_line_board, 'w') = 0 AND INSTR(v_single_line_board, 'W') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной белой фигуры (w, W).';
            RAISE_APPLICATION_ERROR(-20003, v_error_msg);
        END IF;
        IF INSTR(v_single_line_board, 'b') = 0 AND INSTR(v_single_line_board, 'B') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной черной фигуры (b, B).';
            RAISE_APPLICATION_ERROR(-20004, v_error_msg);
        END IF;

        -- Валидация позиции: проверка, что все фигуры находятся на темных клетках
        BEGIN
            p_init_board_map(v_board_size);
            
            FOR i IN 1 .. LENGTH(v_single_line_board) LOOP
                DECLARE
                    v_piece CHAR(1) := SUBSTR(v_single_line_board, i, 1);
                    v_field rec_board_field;
                    v_row PLS_INTEGER;
                    v_col PLS_INTEGER;
                    v_is_dark_square BOOLEAN;
                BEGIN
                    -- Проверяем только фигуры (не пустые клетки)
                    IF v_piece IN ('w', 'W', 'b', 'B') THEN
                        IF NOT g_map_by_idx.EXISTS(i) THEN
                            v_error_msg := 'Ошибка: Недопустимый индекс позиции: ' || i;
                            RAISE_APPLICATION_ERROR(-20007, v_error_msg);
                        END IF;
                        
                        v_field := g_map_by_idx(i);
                        v_row := v_field.row_num;
                        v_col := v_field.col_num;
                        
                        -- Темная клетка: (row + col) % 2 == 1
                        v_is_dark_square := (MOD(v_row + v_col, 2) = 1);
                        
                        IF NOT v_is_dark_square THEN
                            v_error_msg := 'Ошибка: Фигура на позиции ' || v_field.notation || 
                                         ' (индекс ' || i || ', строка ' || v_row || ', столбец ' || v_col || 
                                         ') находится на светлой клетке. В шашках фигуры могут быть только на темных клетках.';
                            RAISE_APPLICATION_ERROR(-20008, v_error_msg);
                        END IF;
                    END IF;
                END;
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN
                -- Если ошибка валидации - пробрасываем дальше
                IF SQLCODE BETWEEN -20007 AND -20008 THEN
                    RAISE;
                ELSE
                    v_error_msg := 'Ошибка при валидации позиции: ' || SQLERRM;
                    RAISE_APPLICATION_ERROR(-20009, v_error_msg);
                END IF;
        END;

        BEGIN
            SELECT rule_id INTO v_rule_id
            FROM game_rules
            WHERE board_size = v_board_size
            AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Ошибка: Не найдено правило в game_rules для доски ' || v_board_size || 'x' || v_board_size;
                RAISE_APPLICATION_ERROR(-20005, v_error_msg);
        END;

        v_encoded_board := encode_board(v_single_line_board);
        
        INSERT INTO puzzles (
            board_position,
            rule_id,
            turn_to_move,
            moves_to_solve,
            difficulty_level,
            created_by_player_id
        ) VALUES (
            v_encoded_board,
            v_rule_id,
            UPPER(p_turn_to_move),
            p_moves_to_solve,
            p_difficulty_level,
            v_player_id
        )
        RETURNING puzzle_id INTO v_new_puzzle_id;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Задача успешно создана (ID: ' || v_new_puzzle_id || ').');
        p_audit_log(v_player_id, NULL, 'PUZZLE_CREATED');

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF v_error_msg IS NULL THEN
               v_error_msg := 'Неизвестная ошибка: ' || SQLERRM;
            END IF;
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 255));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;

END create_puzzle;
-- @procedure show_puzzles
-- @brief Shows a list of available puzzles.
-- @dependencies:
--   - puzzles (table)
--   - players (table)
--   - get_or_create_player_id (function)

PROCEDURE show_puzzles(
    p_difficulty IN CHAR DEFAULT NULL, 
    p_puzzle_id  IN NUMBER DEFAULT NULL
) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_header    VARCHAR2(200);
    v_goal_str  VARCHAR2(50);
    v_visual_board CLOB;
    
    CURSOR c_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            NVL(pl.username, 'System') AS creator_username,
            puz.board_position,
            puz.turn_to_move,
            puz.end_condition
        FROM puzzles puz
        LEFT JOIN players pl ON puz.created_by_player_id = pl.player_id
        WHERE 
            (p_puzzle_id IS NOT NULL AND puz.puzzle_id = p_puzzle_id)
            OR 
            (p_puzzle_id IS NULL AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty))
        ORDER BY puz.puzzle_id;
BEGIN
    v_player_id := get_or_create_player_id(USER);

    -- ВАРИАНТ 1: Поиск конкретной задачи (Красивый вывод)
    IF p_puzzle_id IS NOT NULL THEN
        FOR r IN c_puzzles LOOP
            v_found := TRUE;
            v_goal_str := CASE r.end_condition WHEN 'D' THEN 'Ничья' ELSE 'Победа' END;
            
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE('ЗАДАЧА ID: ' || r.puzzle_id);
            DBMS_OUTPUT.PUT_LINE('Автор:     ' || r.creator_username);
            DBMS_OUTPUT.PUT_LINE('Сложность: ' || r.difficulty_level);
            DBMS_OUTPUT.PUT_LINE('Цель:      ' || v_goal_str || ' за ' || NVL(TO_CHAR(r.moves_to_solve), '?') || ' ход(ов)');
            DBMS_OUTPUT.PUT_LINE('Ваш ход:   ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);
            DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
            
            v_visual_board := f_get_board_as_clob(r.board_position);
            DBMS_OUTPUT.PUT_LINE(v_visual_board);
            DBMS_OUTPUT.PUT_LINE('==================================================');
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('Задача с ID ' || p_puzzle_id || ' не найдена.');
        END IF;
        RETURN;
    END IF;

    -- ВАРИАНТ 2: Общий список (Табличный вывод)
    DBMS_OUTPUT.PUT_LINE('--- Список Доступных Задач ---');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(' (Фильтр по Сложности: ' || p_difficulty || ')');
    ELSE
        DBMS_OUTPUT.PUT_LINE(' (Все задачи)');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 6) || 
        RPAD('Слож.', 6) || 
        RPAD('Ходов', 6) || 
        RPAD('Цель', 7) || 
        RPAD('Автор', 15) || 
        RPAD('Ход', 4) || 
        'Позиция (RLE)'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 6, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 7, '-') || ' ' || RPAD('-', 15, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

    FOR r IN c_puzzles LOOP
        v_found := TRUE;
        v_goal_str := CASE r.end_condition WHEN 'D' THEN 'Ничья' ELSE 'Победа' END;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.puzzle_id, 6) || 
            RPAD(r.difficulty_level, 6) || 
            RPAD(NVL(TO_CHAR(r.moves_to_solve), '?'), 6) || 
            RPAD(SUBSTR(v_goal_str, 1, 6), 7) ||
            RPAD(SUBSTR(r.creator_username, 1, 14), 15) || 
            RPAD(r.turn_to_move, 4) || 
            SUBSTR(r.board_position, 1, 25) || (CASE WHEN LENGTH(r.board_position) > 25 THEN '...' ELSE '' END)
        );
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... Задачи не найдены. ...');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при показе задач: ' || SQLERRM);
END show_puzzles;
-- @procedure show_my_puzzles
-- @brief Shows a list of puzzles created by the current user.
-- @dependencies:
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - f_get_board_as_clob (function)

PROCEDURE show_my_puzzles(p_difficulty IN CHAR DEFAULT NULL) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_visual_board CLOB;
    v_goal_str  VARCHAR2(50);
    
    CURSOR c_my_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            puz.board_position,
            puz.turn_to_move,
            puz.end_condition
        FROM puzzles puz
        WHERE 
            puz.created_by_player_id = v_player_id
            AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty)
        ORDER BY puz.puzzle_id DESC; -- Новые сверху
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    DBMS_OUTPUT.PUT_LINE('==================================================');
    DBMS_OUTPUT.PUT_LINE('              МОИ СОЗДАННЫЕ ЗАДАЧИ');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('           (Фильтр по Сложности: ' || p_difficulty || ')');
    END IF;
    DBMS_OUTPUT.PUT_LINE('==================================================');

    FOR r IN c_my_puzzles LOOP
        v_found := TRUE;
        
        v_goal_str := CASE r.end_condition 
                        WHEN 'D' THEN 'Ничья' 
                        ELSE 'Победа' 
                      END;

        DBMS_OUTPUT.PUT_LINE('ID: ' || r.puzzle_id || ' | Сложность: ' || r.difficulty_level || ' | Цель: ' || v_goal_str || ' за ' || NVL(TO_CHAR(r.moves_to_solve), '?') || ' ход(ов)');
        DBMS_OUTPUT.PUT_LINE('Первый ход: ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);
        
        -- Визуализация
        v_visual_board := f_get_board_as_clob(r.board_position);
        DBMS_OUTPUT.PUT_LINE(v_visual_board);
        DBMS_OUTPUT.PUT_LINE('__________________________________________________'); -- Разделитель
        DBMS_OUTPUT.PUT_LINE(''); -- Пустая строка для отступа
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... У вас нет созданных задач' || 
            CASE WHEN p_difficulty IS NOT NULL THEN ' с заданной сложностью' ELSE '' END || '. ...');
    END IF;
END show_my_puzzles;
-- @procedure delete_my_puzzle
-- @brief Deletes a puzzle created by the current user.
-- @dependencies:
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

-- @procedure delete_my_puzzle
-- @brief Deletes a puzzle created by the current user.
-- [БЕЗ ИЗМЕНЕНИЙ]

PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы удалить задачу.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        DELETE FROM puzzles
        WHERE puzzle_id = p_puzzle_id
          AND created_by_player_id = v_player_id;
          
        IF SQL%ROWCOUNT = 0 THEN
            DECLARE
                v_count PLS_INTEGER;
            BEGIN
                SELECT 1 INTO v_count FROM puzzles WHERE puzzle_id = p_puzzle_id;
                v_error_msg := 'Ошибка: Невозможно удалить задачу. Она не существует или не принадлежит вам.';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_error_msg := 'Ошибка: Задача с ID ' || p_puzzle_id || ' не существует.';
            END;
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
        ELSE
            DBMS_OUTPUT.PUT_LINE('Задача (ID: ' || p_puzzle_id || ') успешно удалена.');
            p_audit_log(v_player_id, NULL, p_event_msg => 'PUZZLE_DELETED');
            COMMIT;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF SQLCODE = -2292 THEN
                v_error_msg := 'Ошибка: Невозможно удалить задачу. Она используется (или использовалась) как "Задача Дня".';
            ELSE
                v_error_msg := 'Ошибка при удалении: ' || SQLERRM;
            END IF;
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 255));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;
END delete_my_puzzle;
-- @procedure show_daily_puzzle
-- @brief Shows the daily puzzle.
-- @dependencies:
--   - daily_puzzles (table)
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - p_audit_log (procedure)
--   - rec_daily_puzzle_info (type)
--   - f_get_board_as_clob (function)

PROCEDURE show_daily_puzzle IS
    v_today       DATE := TRUNC(SYSDATE);
    v_player_id   players.player_id%TYPE;
    
    -- Локальные переменные
    v_puzzle_id      puzzles.puzzle_id%TYPE;
    v_difficulty     puzzles.difficulty_level%TYPE;
    v_moves_solve    puzzles.moves_to_solve%TYPE;
    v_turn           puzzles.turn_to_move%TYPE;
    v_board_pos      puzzles.board_position%TYPE;
    v_end_cond       puzzles.end_condition%TYPE;
    v_author         players.username%TYPE;
    
    v_visual_board   CLOB;
    v_goal_str       VARCHAR2(100);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    BEGIN
        SELECT 
            p.puzzle_id,
            p.difficulty_level,
            p.moves_to_solve,
            p.turn_to_move,
            p.board_position,
            p.end_condition,
            NVL(pl.username, 'System')
        INTO 
            v_puzzle_id, v_difficulty, v_moves_solve, v_turn, v_board_pos, v_end_cond, v_author
        FROM daily_puzzles dp
        JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
        LEFT JOIN players pl ON p.created_by_player_id = pl.player_id
        WHERE dp.puzzle_date = v_today;
        
        v_goal_str := CASE v_end_cond WHEN 'D' THEN 'Ничья' ELSE 'Победа' END;

        DBMS_OUTPUT.PUT_LINE('==================================================');
        DBMS_OUTPUT.PUT_LINE('          ЗАДАЧА ДНЯ (' || TO_CHAR(v_today, 'DD.MM.YYYY') || ')');
        DBMS_OUTPUT.PUT_LINE('==================================================');
        DBMS_OUTPUT.PUT_LINE('ID:        ' || v_puzzle_id);
        -- Не показываем автора если это System
        IF v_author IS NOT NULL AND UPPER(v_author) != 'SYSTEM' THEN
            DBMS_OUTPUT.PUT_LINE('Автор:     ' || v_author);
        END IF;
        DBMS_OUTPUT.PUT_LINE('Сложность: ' || v_difficulty);
        DBMS_OUTPUT.PUT_LINE('Задача:    ' || v_goal_str || ' за ' || NVL(TO_CHAR(v_moves_solve), 'N/A') || ' ход(ов)');
        DBMS_OUTPUT.PUT_LINE('Ваш ход:   ' || CASE v_turn WHEN 'W' THEN 'Белые (W)' ELSE 'Черные (B)' END);
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
        
        -- Рисуем доску
        v_visual_board := f_get_board_as_clob(v_board_pos);
        DBMS_OUTPUT.PUT_LINE(v_visual_board);
        
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
        -- [ИСПРАВЛЕНО] Подсказка для SQL Developer
        DBMS_OUTPUT.PUT_LINE('Для решения: BEGIN game_logic.start_daily_puzzle; END;');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка: Задача на ' || TO_CHAR(v_today, 'DD.MM.YYYY') || ' еще не назначена.');
            p_audit_log(NULL, NULL, p_event_msg => 'DAILY_PUZZLE_NOT_FOUND');
    END;
END show_daily_puzzle;
-- @procedure info
-- @brief Displays help information about the game_logic package.
-- @dependencies:
--   - (none)

PROCEDURE info(p_proc_name IN VARCHAR2 DEFAULT NULL) IS
    c_nl CONSTANT VARCHAR2(1) := CHR(10);
    v_proc_name VARCHAR2(100) := UPPER(TRIM(p_proc_name));
    v_show_all BOOLEAN := (v_proc_name IS NULL OR v_proc_name = '');
    v_found BOOLEAN := FALSE;
BEGIN
    -- Если параметр не передан, показываем подсказку в начале
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle" (v1.2)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Для корректной работы включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('Все команды выполняются в блоках PL/SQL: BEGIN ... END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПОДСКАЗКА: Для просмотра информации по конкретной процедуре передайте параметр:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_proc_name => ''CREATE_GAME''); END;');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE(c_nl);
    END IF;
    
    -- Секция 1: CREATE_GAME
    IF v_show_all OR v_proc_name = 'CREATE_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 1. СОЗДАНИЕ ИГРЫ (CREATE_GAME)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Создает новую игру: PvP (против игрока), PvE (против ИИ) или Puzzle (задача).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (PvP). NULL = открытая игра.');
        DBMS_OUTPUT.PUT_LINE('  p_ai_difficulty       - Сложность ИИ: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard). NULL = PvP.');
        DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные). NULL = случайно.');
        DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10). По умолчанию 1.');
        DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N''. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE('  p_puzzle_id           - ID задачи для решения. NULL = обычная игра.');
        DBMS_OUTPUT.PUT_LINE('  p_daily               - ''Y'' если это задача дня. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Легко, Русские шашки):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_ai_difficulty => ''E'', p_player_color => ''W''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Сложно, Международные 10x10, с таймаутами):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN');
        DBMS_OUTPUT.PUT_LINE('    game_logic.create_game(');
        DBMS_OUTPUT.PUT_LINE('      p_ai_difficulty => ''H'',');
        DBMS_OUTPUT.PUT_LINE('      p_rule_id => 2,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_move_sec => 120,');
        DBMS_OUTPUT.PUT_LINE('      p_draw_moves_limit => 25');
        DBMS_OUTPUT.PUT_LINE('    );');
        DBMS_OUTPUT.PUT_LINE('  END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытая игра (ждет любого соперника):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game; END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Прямой вызов конкретному игроку:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_opponent_username => ''BOB'', p_player_color => ''W''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Решение задачи:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 2: JOIN_GAME
    IF v_show_all OR v_proc_name = 'JOIN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 2. ПРИСОЕДИНЕНИЕ К ИГРЕ (JOIN_GAME)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Присоединяет вас к открытой игре или принимает прямой вызов.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_game_id - ID игры для присоединения.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_game(p_game_id => 123); END;');
        DBMS_OUTPUT.PUT_LINE('  -- После присоединения игра становится активной (статус ''A'')');
        DBMS_OUTPUT.PUT_LINE('  -- и создается джоб таймаута хода (если задан p_time_limit_move_sec)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 3: MAKE_MOVE
    IF v_show_all OR v_proc_name = 'MAKE_MOVE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 3. ХОДЫ (MAKE_MOVE)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Выполняет ход в текущей активной игре.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_move_notation - Нотация хода в формате: начальная-конечная или начальная:конечная');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ФОРМАТ НОТАЦИИ:');
        DBMS_OUTPUT.PUT_LINE('  - Тихий ход: ''a3-b4'' (дефис между полями)');
        DBMS_OUTPUT.PUT_LINE('  - Взятие:    ''c3:e5'' (двоеточие между полями)');
        DBMS_OUTPUT.PUT_LINE('  - Цепочка:   ''c3:e5:g7'' (множественные взятия)');
        DBMS_OUTPUT.PUT_LINE('  - Для 10x10: ''a1-b2'', ''j10:i9:h8'' и т.д.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРАВИЛА ВЗЯТИЙ:');
        DBMS_OUTPUT.PUT_LINE('  - Русские шашки (rule_id=1): Взятие обязательно, можно выбрать ЛЮБОЕ взятие.');
        DBMS_OUTPUT.PUT_LINE('  - Международные (rule_id=2): Взятие обязательно МАКСИМАЛЬНОЕ количество фигур.');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка бьет вперед и назад.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет на любое расстояние с произвольным приземлением.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3-d4''); END;  -- Тихий ход');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5''); END;  -- Взятие');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5:g7''); END; -- Цепочка взятий');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПОСЛЕ ХОДА:');
        DBMS_OUTPUT.PUT_LINE('  - Если игра против ИИ, ИИ автоматически делает ответный ход.');
        DBMS_OUTPUT.PUT_LINE('  - Таймаут хода переносится на следующий ход.');
        DBMS_OUTPUT.PUT_LINE('  - Проверяется окончание игры (победа, ничья, пат).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 4: PRINT_ACTIVE_BOARD
    IF v_show_all OR v_proc_name = 'PRINT_ACTIVE_BOARD' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 4. ПРОСМОТР ДОСКИ (PRINT_ACTIVE_BOARD)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Выводит текущее состояние доски активной игры.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID игры для просмотра. NULL = ваша текущая игра.');
        DBMS_OUTPUT.PUT_LINE('  p_username      - Имя пользователя, чью игру смотреть. NULL = ваша игра.');
        DBMS_OUTPUT.PUT_LINE('  p_wait_for_turn - ''Y'' для ожидания вашего хода. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр вашей текущей игры:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр конкретной игры:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_game_id => 123); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр игры другого пользователя (режим зрителя):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_username => ''GARRY''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Ожидание вашего хода (блокирует до вашей очереди или таймаута):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 5: УПРАВЛЕНИЕ ИГРОЙ
    IF v_show_all OR v_proc_name = 'RESIGN_GAME' OR v_proc_name = 'CANCEL_GAME' OR v_proc_name = 'DRAW' THEN
        IF v_show_all OR v_proc_name = 'RESIGN_GAME' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 5. УПРАВЛЕНИЕ ИГРОЙ');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('5.1. СДАЧА (RESIGN_GAME)');
            DBMS_OUTPUT.PUT_LINE('------------------------');
            DBMS_OUTPUT.PUT_LINE('Сдаться в текущей активной игре.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_resign_match - ''Y'' для сдачи во всем матче. По умолчанию ''N''.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game; END;  -- Сдача в текущей игре');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;  -- Сдача во всем матче');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'CANCEL_GAME' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('5.2. ОТМЕНА ИГРЫ (CANCEL_GAME)');
            DBMS_OUTPUT.PUT_LINE('------------------------------');
            DBMS_OUTPUT.PUT_LINE('Отменяет открытую игру (статус ''O'') или вызов (статус ''C'').');
            DBMS_OUTPUT.PUT_LINE('Нельзя отменить активную игру - используйте resign_game.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.cancel_game; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'DRAW' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('5.3. НИЧЬЯ (DRAW)');
            DBMS_OUTPUT.PUT_LINE('-----------------');
            DBMS_OUTPUT.PUT_LINE('Управление предложениями ничьей (только для PvP игр, не для PvE).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_action - Действие: ''O'' (Offer - предложить), ''A'' (Accept - принять), ''C'' (Cancel/Decline - отменить/отклонить)');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''O''); END;  -- Предложить ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''A''); END;  -- Принять предложение оппонента');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''C''); END;  -- Отменить свое или отклонить чужое предложение');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('АВТОМАТИЧЕСКИЕ НИЧЬИ:');
            DBMS_OUTPUT.PUT_LINE('  - По лимиту ходов без взятий (если задан p_draw_moves_limit)');
            DBMS_OUTPUT.PUT_LINE('  - По повтору позиции (если p_enable_pos_rep_draw = ''Y'')');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 6: МАТЧИ
    IF v_show_all OR v_proc_name = 'CREATE_MATCH' OR v_proc_name = 'JOIN_MATCH' THEN
        IF v_show_all OR v_proc_name = 'CREATE_MATCH' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 6. МАТЧИ (СЕРИИ ИГР)');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('Матч - это серия игр до N побед с одним соперником (best-of-N).');
            DBMS_OUTPUT.PUT_LINE('Цвета чередуются в каждой игре матча.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('6.1. СОЗДАНИЕ МАТЧА (CREATE_MATCH)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента (обязательно).');
            DBMS_OUTPUT.PUT_LINE('  p_games_to_win        - Количество побед для победы в матче (обязательно, > 0).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет в первой игре: ''W''/''B''. NULL = случайно.');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (8x8) или 2 (10x10). По умолчанию 1.');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах.');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на партию в секундах.');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей.');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N''.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_match(');
            DBMS_OUTPUT.PUT_LINE('      p_opponent_username => ''ALICE'',');
            DBMS_OUTPUT.PUT_LINE('      p_games_to_win => 3,');
            DBMS_OUTPUT.PUT_LINE('      p_player_color => ''W'',');
            DBMS_OUTPUT.PUT_LINE('      p_rule_id => 1');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'JOIN_MATCH' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('6.2. ПРИСОЕДИНЕНИЕ К МАТЧУ (JOIN_MATCH)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_match_id - ID матча для присоединения.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('АВТОМАТИЧЕСКОЕ ПРОДОЛЖЕНИЕ МАТЧА:');
            DBMS_OUTPUT.PUT_LINE('  После завершения каждой игры в матче (победа, ничья, таймаут, сдача)');
            DBMS_OUTPUT.PUT_LINE('  система автоматически:');
            DBMS_OUTPUT.PUT_LINE('  - Подсчитывает победы каждого игрока');
            DBMS_OUTPUT.PUT_LINE('  - Если кто-то достиг p_games_to_win побед - завершает матч');
            DBMS_OUTPUT.PUT_LINE('  - Если нет - создает следующую игру с чередованием цвета');
            DBMS_OUTPUT.PUT_LINE('  - Игроки автоматически присоединяются к следующей игре');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_match(p_match_id => 555); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 7: ЗАДАЧИ И ГОЛОВОЛОМКИ
    IF v_show_all OR v_proc_name IN ('SHOW_DAILY_PUZZLE', 'SHOW_PUZZLES', 'SHOW_MY_PUZZLES', 'CREATE_PUZZLE', 'DELETE_MY_PUZZLE') THEN
        IF v_show_all OR v_proc_name = 'SHOW_DAILY_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 7. ЗАДАЧИ И ГОЛОВОЛОМКИ (PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('7.1. ЗАДАЧА ДНЯ (SHOW_DAILY_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('-----------------------------------');
            DBMS_OUTPUT.PUT_LINE('Показывает ежедневную задачу (обновляется автоматически каждый день).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_daily_puzzle; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Затем для решения:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_daily => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'SHOW_PUZZLES' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.2. ПРОСМОТР ЗАДАЧ (SHOW_PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard). NULL = все задачи.');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id  - ID конкретной задачи для детального просмотра. NULL = список всех.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles; END;  -- Список всех задач');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_difficulty => ''E''); END;  -- Только Easy');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_puzzle_id => 10); END;  -- Детальный просмотр с доской');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'SHOW_MY_PUZZLES' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.3. МОИ ЗАДАЧИ (SHOW_MY_PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------');
            DBMS_OUTPUT.PUT_LINE('Показывает задачи, созданные вами.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard). NULL = все ваши задачи.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'CREATE_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.4. СОЗДАНИЕ ЗАДАЧИ (CREATE_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Создает новую задачу из произвольной позиции.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_board_position   - Позиция доски в формате CLOB (многострочный текст).');
            DBMS_OUTPUT.PUT_LINE('                       Каждая строка = один ряд доски (8 или 10 символов).');
            DBMS_OUTPUT.PUT_LINE('                       Символы: ''w''/''W'' (белая простая/дамка), ''b''/''B'' (черная), ''+'' (пусто).');
            DBMS_OUTPUT.PUT_LINE('  p_turn_to_move     - Чей ход: ''W'' (Белые) или ''B'' (Черные).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_solve   - Количество ходов для решения. NULL = без ограничения.');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty_level - Уровень сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard). По умолчанию ''E''.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР (8x8):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_puzzle(');
            DBMS_OUTPUT.PUT_LINE('      p_board_position => ''+b+b+b+b'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''b+b+b+b+'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''+w+w+w+w'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''w+w+w+w+'',');
            DBMS_OUTPUT.PUT_LINE('      p_turn_to_move => ''W'',');
            DBMS_OUTPUT.PUT_LINE('      p_moves_to_solve => 3,');
            DBMS_OUTPUT.PUT_LINE('      p_difficulty_level => ''E''');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'DELETE_MY_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.5. УДАЛЕНИЕ ЗАДАЧИ (DELETE_MY_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Удаляет задачу, созданную вами (нельзя удалить задачу, используемую в игре).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id - ID задачи для удаления.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(15); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all THEN
            DBMS_OUTPUT.PUT_LINE('7.6. РЕШЕНИЕ ЗАДАЧИ');
            DBMS_OUTPUT.PUT_LINE('-------------------');
            DBMS_OUTPUT.PUT_LINE('Для решения задачи используйте create_game с p_puzzle_id:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
            DBMS_OUTPUT.PUT_LINE('Затем делайте ходы как в обычной игре через make_move.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
        END IF;
    END IF;
    
    -- Секция 8: РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ
    IF v_show_all OR v_proc_name IN ('STOP_SPECTATING', 'WATCH_GAME_REPLAY') THEN
        IF v_show_all OR v_proc_name = 'STOP_SPECTATING' THEN
            v_found := TRUE;
            IF v_show_all THEN
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE('## 8. РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ');
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE(c_nl);
                DBMS_OUTPUT.PUT_LINE('8.1. ПРОСМОТР АКТИВНОЙ ИГРЫ (PRINT_ACTIVE_BOARD)');
                DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
                DBMS_OUTPUT.PUT_LINE('Если вы не участник игры, автоматически входите в режим зрителя.');
                DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_username => ''GARRY''); END;');
                DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_game_id => 123); END;');
                DBMS_OUTPUT.PUT_LINE(c_nl);
            END IF;
            
            DBMS_OUTPUT.PUT_LINE('8.2. ВЫХОД ИЗ РЕЖИМА ЗРИТЕЛЯ (STOP_SPECTATING)');
            DBMS_OUTPUT.PUT_LINE('-----------------------------------------------');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.stop_spectating; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'WATCH_GAME_REPLAY' THEN
            v_found := TRUE;
            IF v_show_all THEN
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE('## 8. РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ');
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE(c_nl);
            END IF;
            
            DBMS_OUTPUT.PUT_LINE('8.3. ПРОСМОТР РЕПЛЕЯ (WATCH_GAME_REPLAY)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Просматривает ходы завершенной игры пошагово.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID завершенной игры (статус ''V'', ''D'', ''T'', ''R'').');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_show - Количество ходов для показа за один вызов. По умолчанию 1.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  -- Показать первые 3 хода:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 3); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Вызывайте повторно для просмотра следующих ходов');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 9: ПРАВИЛА ИГРЫ (только при полном выводе)
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 9. ПРАВИЛА ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('РУССКИЕ ШАШКИ (rule_id = 1, доска 8x8):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно, но можно выбрать ЛЮБОЕ взятие.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('МЕЖДУНАРОДНЫЕ ШАШКИ (rule_id = 2, доска 10x10):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно МАКСИМАЛЬНОЕ количество фигур.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ОБЩИЕ ПРАВИЛА:');
        DBMS_OUTPUT.PUT_LINE('  - Белые начинают первыми.');
        DBMS_OUTPUT.PUT_LINE('  - Пат (нет ходов) = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Отсутствие фигур = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: по соглашению, по лимиту ходов без взятий, по повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
    END IF;
    
    -- Секции 10-15: Общая информация (только при полном выводе)
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 10. ПАРАМЕТРЫ ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ТАЙМАУТЫ:');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_move_sec: Лимит времени на один ход (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Если время истекает, игрок проигрывает (статус ''T'' - Timeout).');
        DBMS_OUTPUT.PUT_LINE('    Джоб таймаута создается при join_game и переносится при каждом ходе.');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_game_sec: Лимит времени на всю партию (в секундах).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('НИЧЬИ:');
        DBMS_OUTPUT.PUT_LINE('  - p_draw_moves_limit: Количество полуходов без взятий для автоматической ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Например, 15 означает, что после 15 полуходов без взятий игра заканчивается ничьей.');
        DBMS_OUTPUT.PUT_LINE('  - p_enable_pos_rep_draw: ''Y'' включает ничью по троекратному повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПРИМЕР ИГРЫ С ВСЕМИ ПАРАМЕТРАМИ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN');
        DBMS_OUTPUT.PUT_LINE('    game_logic.create_game(');
        DBMS_OUTPUT.PUT_LINE('      p_opponent_username => ''BOB'',');
        DBMS_OUTPUT.PUT_LINE('      p_player_color => ''W'',');
        DBMS_OUTPUT.PUT_LINE('      p_rule_id => 1,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_move_sec => 60,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_game_sec => 3600,');
        DBMS_OUTPUT.PUT_LINE('      p_draw_moves_limit => 15,');
        DBMS_OUTPUT.PUT_LINE('      p_enable_pos_rep_draw => ''Y''');
        DBMS_OUTPUT.PUT_LINE('    );');
        DBMS_OUTPUT.PUT_LINE('  END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 11. СТАТУСЫ ИГР');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  ''O'' - Open (Открытая, ждет соперника)');
        DBMS_OUTPUT.PUT_LINE('  ''C'' - Challenged (Вызов, ждет принятия)');
        DBMS_OUTPUT.PUT_LINE('  ''A'' - Active (Активная, идет игра)');
        DBMS_OUTPUT.PUT_LINE('  ''V'' - Victory (Победа одного из игроков)');
        DBMS_OUTPUT.PUT_LINE('  ''D'' - Draw (Ничья)');
        DBMS_OUTPUT.PUT_LINE('  ''T'' - Timeout (Таймаут)');
        DBMS_OUTPUT.PUT_LINE('  ''R'' - Resigned (Сдача)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 12. ПРЕДСТАВЛЕНИЯ (VIEWS) ДЛЯ СТАТИСТИКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Используйте SQL запросы для просмотра статистики:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Статус игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_status WHERE game_id = 123;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Протокол игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_protocol WHERE game_id = 123 ORDER BY move_number;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока за период:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history_by_period;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Статистика игрока:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_stats;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинг по успеху:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_leaderboard;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинг по среднему числу ходов:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_leaderboard_by_avg_moves;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Результаты Daily Puzzles:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 13. РЕЙТИНГИ И СЕЗОНЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Начальный рейтинг нового игрока: 500 для всех правил.');
        DBMS_OUTPUT.PUT_LINE('  - Победа в обычной игре: +16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Поражение в обычной игре: -16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Решение задачи (первый раз): +5 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: рейтинг не меняется.');
        DBMS_OUTPUT.PUT_LINE('  - Минимальный рейтинг: 0 (не может быть отрицательным).');
        DBMS_OUTPUT.PUT_LINE('  - Сезоны обновляются автоматически каждый месяц (scheduler).');
        DBMS_OUTPUT.PUT_LINE('  - Формат сезона: "Месяц-Год" (например, "Январь-2025").');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 14. ОГРАНИЧЕНИЯ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Один пользователь может иметь только одну активную сессию.');
        DBMS_OUTPUT.PUT_LINE('  - Активная сессия = игра (статус ''A'', ''O'', ''C'') или просмотр (spectating).');
        DBMS_OUTPUT.PUT_LINE('  - При попытке создать вторую игру будет ошибка.');
        DBMS_OUTPUT.PUT_LINE('  - Длительное простаивание автоматически завершает сессию (scheduler).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 15. БЫСТРЫЙ СТАРТ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('1. Включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('2. Посмотрите справку: BEGIN game_logic.info; END;');
        DBMS_OUTPUT.PUT_LINE('3. Создайте игру против ИИ:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
        DBMS_OUTPUT.PUT_LINE('4. Посмотрите доску:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE('5. Сделайте ход:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.make_move(''c3-d4''); END;');
        DBMS_OUTPUT.PUT_LINE('6. ИИ автоматически ответит, и вы увидите обновленную доску.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Рейтинг: Победа +16, Поражение -16, Пазл +5 (первый раз).');
        DBMS_OUTPUT.PUT_LINE('Удачи в игре!');
        DBMS_OUTPUT.PUT_LINE('================================================================');
    END IF;
    
    -- Если процедура не найдена, выводим сообщение
    IF NOT v_show_all AND NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: Процедура "' || v_proc_name || '" не найдена.');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('Для полной справки: BEGIN game_logic.info; END;');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;


--------------------------------------------------------------------------------
BEGIN -- Package Initialization Block
    NULL;
END game_logic;