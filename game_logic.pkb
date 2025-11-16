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
        notation VARCHAR2(2),
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

    -- Эти типы теперь объявлены в спецификации, т.к. используются "публичными" функциями
    -- TYPE r_move_step IS RECORD(...);
    -- TYPE t_move_path IS TABLE OF r_move_step;
    -- TYPE r_move IS RECORD(...);
    -- TYPE t_move_list IS TABLE OF r_move;
    -- TYPE t_map_indices IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    -- TYPE r_minimax_result IS RECORD (...);

    --------------------------------------------------------------------------------
    -- Функции кодирования/декодирования RLE
    --------------------------------------------------------------------------------

    /**
     * @function encode_board
     * @brief Сжимает (кодирует) строку доски с помощью RLE.
     */
    FUNCTION encode_board(p_decoded_board IN VARCHAR2) RETURN VARCHAR2 IS
        v_encoded_board VARCHAR2(100) := '';
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

    /**
     * @function decode_board
     * @brief Расжимает (декодирует) RLE-строку доски в полную строку.
     */
    FUNCTION decode_board(p_encoded_board IN VARCHAR2) RETURN VARCHAR2 IS
        v_decoded_board VARCHAR2(100) := '';
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

    --------------------------------------------------------------------------------

    FUNCTION get_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
        v_game_id games.game_id%TYPE;
    BEGIN
        SELECT g.game_id
        INTO v_game_id
        FROM games g
        WHERE g.status IN ('A', 'O', 'C') -- Активна, Открыта (мной) или Вызов (мной/мне)
        AND (g.player_white_id = p_user_id OR g.player_black_id = p_user_id)
        AND ROWNUM = 1;

        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END get_active_game;

    --------------------------------------------------------------------------------

    FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
        v_player_id players.player_id%TYPE;
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
        END;
        RETURN v_player_id;
    END get_or_create_player_id;

    --------------------------------------------------------------------------------

    FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
        v_rule      game_rules%ROWTYPE;
        v_error_msg VARCHAR2(200); -- Переменная для сообщения об ошибке
    BEGIN
        -- Сначала пытаемся найти правило
        BEGIN
            SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Обработка случая, если ID правила вообще не найден в таблице
                v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
                
                -- 1) Запись в аудит
                p_audit_log(
                    p_player_id => NULL,
                    p_game_id   => NULL,
                    p_event_type => v_error_msg
                );
                
                -- 2) Вывод DBMS_OUTPUT
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                
                -- 3) Завершение функции
                RETURN NULL;
        END;

        -- [ИЗМЕНЕНИЕ] Правило найдено, проверяем РАЗМЕР ДОСКИ
        IF v_rule.board_size = 8 THEN
            -- 8x8 (Например, Русские шашки)
            RETURN '+b+b+b+b' || -- Row 8
                'b+b+b+b+' || -- Row 7
                '+b+b+b+b' || -- Row 6
                '++++++++' || -- Row 5
                '++++++++' || -- Row 4
                'w+w+w+w+' || -- Row 3
                '+w+w+w+w' || -- Row 2
                'w+w+w+w+';  -- Row 1 (Всего 64 символа)

        ELSIF v_rule.board_size = 10 THEN
            -- 10x10 (Например, Международные шашки)
            RETURN 'b+b+b+b+b' || -- Row 10
                '+b+b+b+b+b' || -- Row 9
                'b+b+b+b+b' || -- Row 8
                '+b+b+b+b+b' || -- Row 7
                '++++++++++' || -- Row 6
                '++++++++++' || -- Row 5
                'w+w+w+w+w' || -- Row 4
                '+w+w+w+w+w' || -- Row 3
                'w+w+w+w+w' || -- Row 2
                '+w+w+w+w+w'; -- Row 1 (Всего 100 символов)
        ELSE
            -- Неподдерживаемый размер
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' (Размер: ' || v_rule.board_size || ') не поддерживаются.';
            
            -- 1) Запись в аудит
            p_audit_log(
                p_player_id => NULL,
                p_game_id   => NULL,
                p_event_type => v_error_msg
            );
            
            -- 2) Вывод DBMS_OUTPUT
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            
            -- 3) Завершение функции
            RETURN NULL;
        END IF;
    END get_initial_position;

    ---------------------------------------------------------------------------------
    
    /**
     * @procedure p_init_board_map
     * @brief (НОВАЯ) Инициализирует или перестраивает глобальные карты (g_map_by_notation, g_map_by_idx)
     * для доски заданного размера. Работает как кэш: если карта нужного
     * размера уже создана, ничего не делает.
     */
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
                v_idx := ((p_board_size - r) * p_board_size) + c;
                
                -- Нотация (например, 'a1', 'h8', 'j10')
                v_notation := CHR(ASCII('a') + c - 1);
                IF c > 8 THEN -- Для 10x10 (i, j)
                   v_notation := CHR(ASCII('a') + c - 1);
                END IF;
                v_notation := v_notation || r;

                -- Собираем запись
                v_field_rec.idx        := v_idx;
                v_field_rec.notation   := v_notation;
                v_field_rec.row_num    := r;
                v_field_rec.col_num    := c;

                -- Заполняем ОБЕ карты
                g_map_by_notation(v_notation) := v_field_rec;
                g_map_by_idx(v_idx)           := v_field_rec;
                
            END LOOP;
        END LOOP;
        
        -- 4. Обновляем "флаг" кэша
        g_current_map_size := p_board_size;
        
    END p_init_board_map;

    --------------------------------------------------------------------------------

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

    --------------------------------------------------------------------------------

    FUNCTION find_capture_paths(
        p_start_idx    IN PLS_INTEGER,
        p_board        IN VARCHAR2,
        p_player_color IN CHAR,
        p_is_king      IN CHAR,
        p_rule_id      IN NUMBER,
        p_visited_path IN t_move_path DEFAULT t_move_path()
    ) RETURN t_move_list IS
        v_results         t_move_list := t_move_list();
        v_leaf_paths      t_move_list := t_move_list();
        v_opponent_man    CHAR(1);
        v_opponent_king   CHAR(1);
        v_decoded_board   VARCHAR2(100) := decode_board(p_board);
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные
        v_rule            game_rules%ROWTYPE;
        v_board_size      PLS_INTEGER;
        v_total_squares   PLS_INTEGER;
        v_promotion_row   PLS_INTEGER;
        v_max_king_range  PLS_INTEGER;
        v_jump_directions SYS.ODCINUMBERLIST;
        v_start_field     rec_board_field;
        
    BEGIN
        -- [ИЗМЕНЕНИЕ] Блок настройки на основе p_rule_id
        BEGIN
            SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
            v_board_size      := v_rule.board_size;
            v_total_squares   := v_board_size * v_board_size;
            v_promotion_row   := v_board_size; -- 8 для 8x8, 10 для 10x10
            v_max_king_range  := v_board_size - 1; -- 7 для 8x8, 9 для 10x10
            
            -- Инициализируем кэш карт (g_map_by_idx, g_map_by_notation)
            p_init_board_map(v_board_size);
            
            -- Получаем стартовое поле из нового кэша
            v_start_field := g_map_by_idx(p_start_idx);

            -- Устанавливаем смещения для прыжков
            IF v_board_size = 8 THEN
                v_jump_directions := SYS.ODCINUMBERLIST(-18, -14, 14, 18);
            ELSE -- 10 (или любое другое, но мы пока поддерживаем 10)
                v_jump_directions := SYS.ODCINUMBERLIST(-22, -18, 18, 22);
            END IF;
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_audit_log(NULL, NULL, 'find_capture_paths: Rule_id ' || p_rule_id || ' не найден.');
                RETURN v_results; -- Возвращаем пустой список
            WHEN OTHERS THEN
                p_audit_log(NULL, NULL, 'find_capture_paths: Ошибка инициализации карты для idx ' || p_start_idx);
                RETURN v_results; -- Возвращаем пустой список
        END;
        
        -- Определение оппонента (без изменений)
        IF p_player_color = 'W' THEN
            v_opponent_man  := c_black_man;
            v_opponent_king := c_black_king;
        ELSE
            v_opponent_man  := c_white_man;
            v_opponent_king := c_white_king;
        END IF;

        -- Основной цикл (без изменений)
        FOR i IN 1 .. v_jump_directions.COUNT LOOP
            DECLARE
                v_jump        PLS_INTEGER := v_jump_directions(i);
                v_land_idx    PLS_INTEGER;
                v_capture_idx PLS_INTEGER;
                v_is_visited  BOOLEAN := FALSE;
                -- v_start_field уже получена выше
            BEGIN
                IF p_is_king = 'N' THEN
                    v_land_idx    := p_start_idx + v_jump;
                    v_capture_idx := p_start_idx + (v_jump / 2);

                    -- [ИЗМЕНЕНИЕ] Используем v_total_squares и новый кэш g_map_by_idx
                    IF v_land_idx BETWEEN 1 AND v_total_squares AND g_map_by_idx.EXISTS(v_land_idx)
                       AND ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) = 2 
                    THEN
                        IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field AND SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN
                            FOR k IN 1 .. p_visited_path.COUNT LOOP
                                IF p_visited_path(k).captured_idx = v_capture_idx THEN
                                    v_is_visited := TRUE;
                                    EXIT;
                                END IF;
                            END LOOP;

                            IF NOT v_is_visited THEN
                                DECLARE
                                    v_becomes_king      CHAR(1) := 'N';
                                    -- [ИЗМЕНЕНИЕ] Используем новый кэш g_map_by_idx
                                    v_land_row          PLS_INTEGER := g_map_by_idx(v_land_idx).row_num; 
                                    -- [ИЗМЕНЕНИЕ] Используем v_promotion_row
                                    v_is_promotion_square BOOLEAN := (p_player_color = 'W' AND v_land_row = v_promotion_row) OR (p_player_color = 'B' AND v_land_row = 1);
                                    v_step              r_move_step;
                                    v_new_path          t_move_path := p_visited_path;
                                    v_sub_paths         t_move_list;
                                    v_move              r_move;
                                BEGIN
                                    v_step.start_idx    := p_start_idx;
                                    v_step.end_idx      := v_land_idx;
                                    v_step.captured_idx := v_capture_idx;
                                    v_new_path.EXTEND;
                                    v_new_path(v_new_path.LAST) := v_step;

                                    IF p_rule_id = 1 AND v_is_promotion_square THEN
                                        v_becomes_king := 'Y';
                                    END IF;

                                    -- Рекурсивный вызов (без изменений)
                                    v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, v_becomes_king, p_rule_id, v_new_path);

                                    IF v_sub_paths.COUNT = 0 THEN
                                        v_move.path           := v_new_path;
                                        v_move.is_capture     := 'Y';
                                        v_move.capture_count  := v_new_path.COUNT;
                                        v_leaf_paths.EXTEND;
                                        v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                    ELSE
                                        FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                            v_results.EXTEND;
                                            v_results(v_results.LAST) := v_sub_paths(j);
                                        END LOOP;
                                    END IF;
                                END;
                            END IF;
                        END IF;
                    END IF;
                ELSE -- King logic
                    -- [ИЗМЕНЕНИЕ] Используем v_max_king_range
                    FOR k IN 1 .. v_max_king_range LOOP 
                        v_capture_idx := p_start_idx + (v_jump / 2 * k);

                        -- [ИЗМЕНЕНИЕ] Используем v_total_squares и новый кэш g_map_by_idx
                        IF v_capture_idx NOT BETWEEN 1 AND v_total_squares OR NOT g_map_by_idx.EXISTS(v_capture_idx)
                           OR ABS(v_start_field.col_num - g_map_by_idx(v_capture_idx).col_num) != k 
                        THEN
                            EXIT;
                        END IF;

                        IF SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN
                            FOR m IN 1 .. p_visited_path.COUNT LOOP
                                IF p_visited_path(m).captured_idx = v_capture_idx THEN
                                    v_is_visited := TRUE;
                                    EXIT;
                                END IF;
                            END LOOP;
                            IF v_is_visited THEN EXIT; END IF;

                            -- [ИЗМЕНЕНИЕ] Используем v_board_size
                            FOR l IN (k + 1) .. v_board_size LOOP 
                                v_land_idx := p_start_idx + (v_jump / 2 * l);
                                
                                -- [ИЗМЕНЕНИЕ] Используем v_total_squares и новый кэш g_map_by_idx
                                IF v_land_idx NOT BETWEEN 1 AND v_total_squares OR NOT g_map_by_idx.EXISTS(v_land_idx)
                                   OR ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) != l 
                                THEN
                                    EXIT;
                                END IF;
                                
                                DECLARE
                                    -- [ИЗМЕНЕНИЕ] Используем новый кэш g_map_by_idx
                                    v_land_field rec_board_field := g_map_by_idx(v_land_idx);
                                BEGIN
                                    IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field AND MOD(v_land_field.row_num + v_land_field.col_num, 2) = 0 THEN
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
                                            
                                            v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, 'Y', p_rule_id, v_new_path);

                                            IF v_sub_paths.COUNT = 0 THEN
                                                v_move.path           := v_new_path;
                                                v_move.is_capture     := 'Y';
                                                v_move.capture_count  := v_new_path.COUNT;
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
                                        EXIT;
                                    END IF;
                                END;
                            END LOOP;
                            EXIT;
                        END IF;
                    END LOOP;
                END IF;
            END;
        END LOOP;
        
        -- Логика выбора максимального пути (без изменений)
        IF v_results.COUNT > 0 THEN
            RETURN v_results;
        ELSE
            RETURN v_leaf_paths;
        END IF;

    END find_capture_paths;

    --------------------------------------------------------------------------------

    FUNCTION find_all_player_moves(
        p_board        IN VARCHAR2,
        p_player_color IN CHAR,
        p_rule_id      IN NUMBER
    ) RETURN t_move_list IS
        v_all_moves     t_move_list := t_move_list();
        v_capture_moves t_move_list := t_move_list();
        v_simple_moves  t_move_list := t_move_list();
        v_player_man    CHAR(1);
        v_player_king   CHAR(1);
        v_max_captures  PLS_INTEGER := 0;
        v_decoded_board VARCHAR2(200) := decode_board(p_board); -- Увеличено для 10x10
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные
        v_rule            game_rules%ROWTYPE;
        v_board_size      PLS_INTEGER;
        v_total_squares   PLS_INTEGER;
        v_simple_move_w   SYS.ODCINUMBERLIST;
        v_simple_move_b   SYS.ODCINUMBERLIST;
        v_simple_move_all SYS.ODCINUMBERLIST;
        v_max_king_range  PLS_INTEGER;

    BEGIN
        -- [ИЗМЕНЕНИЕ] Блок настройки на основе p_rule_id
        BEGIN
            SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
            v_board_size      := v_rule.board_size;
            v_total_squares   := v_board_size * v_board_size;
            v_max_king_range  := v_board_size - 1; -- 7 для 8x8, 9 для 10x10
            
            -- Инициализируем кэш карт (g_map_by_idx, g_map_by_notation)
            p_init_board_map(v_board_size);
            
            -- Устанавливаем смещения для ходов
            IF v_board_size = 8 THEN
                v_simple_move_w   := SYS.ODCINUMBERLIST(-9, -7);
                v_simple_move_b   := SYS.ODCINUMBERLIST(7, 9);
                v_simple_move_all := SYS.ODCINUMBERLIST(-9, -7, 7, 9);
            ELSE -- 10
                v_simple_move_w   := SYS.ODCINUMBERLIST(-11, -9);
                v_simple_move_b   := SYS.ODCINUMBERLIST(9, 11);
                v_simple_move_all := SYS.ODCINUMBERLIST(-11, -9, 9, 11);
            END IF;
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_audit_log(NULL, NULL, 'find_all_player_moves: Rule_id ' || p_rule_id || ' не найден.');
                RETURN v_all_moves; -- Возвращаем пустой список
        END;

        -- Определение фигур (без изменений)
        IF p_player_color = 'W' THEN
            v_player_man  := c_white_man;
            v_player_king := c_white_king;
        ELSE
            v_player_man  := c_black_man;
            v_player_king := c_black_king;
        END IF;
        
        -- === 1. ПОИСК ВЗЯТИЙ ===
        -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
        FOR i IN 1 .. v_total_squares LOOP
            DECLARE
                v_piece   CHAR(1) := SUBSTR(v_decoded_board, i, 1);
                v_paths   t_move_list;
                v_is_king CHAR(1);
            BEGIN
                IF v_piece IN (v_player_man, v_player_king) THEN
                    v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;
                    -- Вызов find_capture_paths (без изменений)
                    v_paths   := find_capture_paths(i, v_decoded_board, p_player_color, v_is_king, p_rule_id);
                    
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

        -- === 2. ФИЛЬТРАЦИЯ ВЗЯТИЙ (Правило "Максимального взятия") ===
        IF v_capture_moves.COUNT > 0 THEN
            -- [ИЗМЕНЕНИЕ] Логика стала более явной
            -- Для Русских шашек (id=1) ОБЯЗАТЕЛЬНО взятие, но ЛЮБОЕ
            IF p_rule_id = 1 THEN 
                RETURN v_capture_moves;
            ELSE 
            -- Для Международных (id=2) ОБЯЗАТЕЛЬНО МАКСИМАЛЬНОЕ взятие
                FOR i IN 1 .. v_capture_moves.COUNT LOOP
                    IF v_capture_moves(i).capture_count = v_max_captures THEN
                        v_all_moves.EXTEND;
                        v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                    END IF;
                END LOOP;
                RETURN v_all_moves;
            END IF;
        END IF;

        -- === 3. ПОИСК "ТИХИХ" ХОДОВ (Если взятий не найдено) ===
        -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
        FOR i IN 1 .. v_total_squares LOOP
            DECLARE
                v_piece       CHAR(1) := SUBSTR(v_decoded_board, i, 1);
                v_start_field rec_board_field := g_map_by_idx(i); -- Используем кэш
            BEGIN
                IF v_piece = v_player_man THEN
                    DECLARE
                        v_directions SYS.ODCINUMBERLIST;
                    BEGIN
                        -- [ИЗМЕНЕНИЕ] Используем динамические смещения
                        IF p_player_color = 'W' THEN
                            v_directions := v_simple_move_w;
                        ELSE
                            v_directions := v_simple_move_b;
                        END IF;
                        
                        FOR d IN 1 .. v_directions.COUNT LOOP
                            DECLARE
                                v_end_idx   PLS_INTEGER := i + v_directions(d);
                                v_end_field rec_board_field;
                            BEGIN
                                -- [ИЗМЕНЕНИЕ] Проверка через кэш
                                IF g_map_by_idx.EXISTS(v_end_idx) AND SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                    v_end_field := g_map_by_idx(v_end_idx);
                                    
                                    -- Проверка геометрии (чтобы не перепрыгнуть край)
                                    IF ABS(v_start_field.col_num - v_end_field.col_num) = 1 THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx      := i;
                                            v_step.end_idx        := v_end_idx;
                                            v_step.captured_idx   := NULL;
                                            v_move.path           := t_move_path(v_step);
                                            v_move.is_capture     := 'N';
                                            v_move.capture_count  := 0;
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
                        -- [ИЗМЕНЕНИЕ] Используем v_simple_move_all
                        v_directions SYS.ODCINUMBERLIST := v_simple_move_all;
                    BEGIN
                        FOR d IN 1 .. v_directions.COUNT LOOP
                            -- [ИЗМЕНЕНИЕ] Используем v_max_king_range
                            FOR k IN 1 .. v_max_king_range LOOP 
                                DECLARE
                                    v_end_idx   PLS_INTEGER := i + (v_directions(d) * k);
                                    v_end_field rec_board_field;
                                BEGIN
                                    -- [ИЗМЕНЕНИЕ] Проверка выхода за доску через кэш
                                    IF NOT g_map_by_idx.EXISTS(v_end_idx) THEN
                                        EXIT;
                                    END IF;
                                    
                                    v_end_field := g_map_by_idx(v_end_idx);
                                    
                                    -- [ИЗМЕНЕНИЕ] Проверка геометрии через кэш
                                    IF k > 1 AND ABS(g_map_by_idx(i + (v_directions(d) * (k - 1))).col_num - v_end_field.col_num) != 1 THEN
                                        EXIT;
                                    END IF;

                                    IF SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx      := i;
                                            v_step.end_idx        := v_end_idx;
                                            v_step.captured_idx   := NULL;
                                            v_move.path           := t_move_path(v_step);
                                            v_move.is_capture     := 'N';
                                            v_move.capture_count  := 0;
                                            v_simple_moves.EXTEND;
                                            v_simple_moves(v_simple_moves.LAST) := v_move;
                                        END;
                                    ELSE
                                        EXIT;
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


    /**
     * @function get_sorted_possible_moves
     * @brief Gets all possible moves and sorts them based on a heuristic score.
     * This is critical for making alpha-beta pruning effective.
     */
    FUNCTION get_sorted_possible_moves(
        p_board IN VARCHAR2,
        p_color IN CHAR
    ) RETURN t_move_list IS
        v_moves t_move_list;
        v_temp  r_move; -- A temporary record for swapping
    BEGIN
        v_moves := find_all_player_moves(p_board, p_color, 1); -- Assuming rule_id=1
        
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
        
        -- << ERROR FIX >>
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

    --------------------------------------------------------------------------------
    
    
    /**
     * @function evaluate_board
     * @brief Assigns a numerical score to a given board position.
     * Positive scores favor the AI, negative scores favor the opponent.
     */
    FUNCTION evaluate_board(
        p_board       IN VARCHAR2,
        p_ai_color    IN CHAR,
        p_difficulty  IN NUMBER
    ) RETURN NUMBER IS
        v_score         NUMBER := 0;
        v_piece         CHAR(1);
        
        -- Weights for pieces and positions, as per the Python example
        c_man_value     CONSTANT NUMBER := 10;
        c_king_value    CONSTANT NUMBER := 50;
        c_side_val      CONSTANT NUMBER := 20; -- Bonus for being on side columns
        c_wall_val      CONSTANT NUMBER := 10; -- Bonus for advancing up the board

    BEGIN
        FOR i IN 1..64 LOOP
            v_piece := SUBSTR(p_board, i, 1);
            IF v_piece != c_empty_field THEN
                DECLARE
                    v_piece_value   NUMBER;
                    v_multiplier    NUMBER;
                    v_piece_color   CHAR(1);
                    v_row           PLS_INTEGER := 8 - TRUNC((i - 1) / 8); -- Row (1-8)
                    v_col           PLS_INTEGER := MOD(i - 1, 8) + 1;     -- Col (1-8)
                    v_position_bonus NUMBER := 0;
                BEGIN
                    -- 1. Determine piece ownership and value
                    v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                    v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                    v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                    
                    -- Add the basic material score
                    v_score := v_score + (v_piece_value * v_multiplier);

                    -- 2. Calculate and add positional bonuses (SIDE_VAL and WALL_VAL)
                    -- This logic only applies to non-hard difficulty as a simplification for now
                    -- On hard, the pure search depth is more important.
                    IF p_difficulty < 2 THEN
                        -- SIDE_VAL: Bonus for pieces on the 'a' or 'h' columns
                        IF v_col = 1 OR v_col = 8 THEN
                            v_position_bonus := v_position_bonus + c_side_val;
                        END IF;

                        -- WALL_VAL: Linear bonus for how far a piece has advanced.
                        -- A piece on the back rank gets a small bonus, a piece about to be promoted gets the max bonus.
                        IF v_piece_color = 'W' THEN
                           v_position_bonus := v_position_bonus + ( (v_row / 8) * c_wall_val );
                        ELSE -- Piece is Black
                           v_position_bonus := v_position_bonus + ( ((9 - v_row) / 8) * c_wall_val );
                        END IF;
                    END IF;
                    
                    v_score := v_score + (v_position_bonus * v_multiplier);
                END;
            END IF;
        END LOOP;
        
        -- Check for terminal win/loss state
        DECLARE
            v_ai_pieces     PLS_INTEGER := 0;
            v_opp_pieces    PLS_INTEGER := 0;
            v_opp_color     CHAR(1) := CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END;
        BEGIN
            FOR k IN 1..64 LOOP
                 IF SUBSTR(p_board, k, 1) != c_empty_field THEN
                    IF (CASE WHEN SUBSTR(p_board, k, 1) IN ('w', 'W') THEN 'W' ELSE 'B' END) = p_ai_color THEN
                        v_ai_pieces := 1;
                    ELSE
                        v_opp_pieces := 1;
                    END IF;
                 END IF;
                 -- Exit early if we've found pieces for both sides
                 IF v_ai_pieces > 0 AND v_opp_pieces > 0 THEN
                    EXIT;
                 END IF;
            END LOOP;

            IF v_ai_pieces > 0 AND v_opp_pieces = 0 THEN
                RETURN 9999; -- AI has won
            ELSIF v_ai_pieces = 0 AND v_opp_pieces > 0 THEN
                RETURN -9999; -- AI has lost
            END IF;
        END;

        RETURN v_score;
    END evaluate_board;

    /**
     * @function apply_move_to_board
     * @brief Simulates a move and returns the new board state as a string.
     * This is a non-database version of p_process_move's logic.
     */
    FUNCTION apply_move_to_board(
        p_board IN VARCHAR2,
        p_move  IN r_move,
        p_color IN CHAR
    ) RETURN VARCHAR2 IS
        v_new_board     VARCHAR2(100) := p_board;
        v_moving_piece  CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
        v_start_pos     PLS_INTEGER := p_move.path(1).start_idx;
        v_end_pos       PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
        v_promoted      BOOLEAN := FALSE;
    BEGIN
        v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

        IF p_move.is_capture = 'Y' THEN
            FOR i IN 1..p_move.path.COUNT LOOP
                v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
            END LOOP;
        END IF;

        IF v_moving_piece IN (c_white_man, c_black_man) THEN
            DECLARE
                v_end_row PLS_INTEGER := g_board_map(idx_to_notation(v_end_pos)).row_num;
                v_is_promotion BOOLEAN := (p_color = 'W' AND v_end_row = 8) OR (p_color = 'B' AND v_end_row = 1);
            BEGIN
                IF v_is_promotion THEN
                    v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                END IF;
            END;
        END IF;

        v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
        RETURN v_new_board;
    END apply_move_to_board;


/**
     * @function minimax
     * @brief The core recursive Minimax algorithm with Alpha-Beta Pruning.
     */
    FUNCTION minimax(
        p_board             IN VARCHAR2,
        p_depth             IN PLS_INTEGER,
        p_alpha             IN NUMBER, 
        p_beta              IN NUMBER, 
        p_is_maximizing     IN BOOLEAN,
        p_ai_color          IN CHAR,
        p_difficulty        IN NUMBER
    ) RETURN r_minimax_result IS
        v_result r_minimax_result;
        v_possible_moves t_move_list; -- Stays the same
        v_current_color  CHAR(1);
        v_local_alpha    NUMBER := p_alpha;
        v_local_beta     NUMBER := p_beta;
    BEGIN
        v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;
        
        -- << CRITICAL CHANGE HERE >>
        -- Use the new sorting function
        v_possible_moves := get_sorted_possible_moves(p_board, v_current_color);

        IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN
            v_result.score := evaluate_board(p_board, p_ai_color, p_difficulty);
            v_result.move := NULL;
            RETURN v_result;
        END IF;
        
        IF p_is_maximizing THEN
            v_result.score := -99999; 
            FOR i IN 1..v_possible_moves.COUNT LOOP
                DECLARE
                    v_new_board     VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                    v_eval_result   r_minimax_result;
                BEGIN
                    v_eval_result := minimax(v_new_board, p_depth - 1, v_local_alpha, v_local_beta, FALSE, p_ai_color, p_difficulty);
                    
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
                    v_new_board   VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                    v_eval_result r_minimax_result;
                BEGIN
                    v_eval_result := minimax(v_new_board, p_depth - 1, v_local_alpha, v_local_beta, TRUE, p_ai_color, p_difficulty);

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

-- =========================================================================
    -- [ПРИВАТНЫЕ ЗАГЛУШКИ]
    -- Эти процедуры должны быть реализованы для "Отлично"
    -- =========================================================================
    PROCEDURE p_audit_log(
        p_player_id  IN players.player_id%TYPE,
        p_game_id    IN games.game_id%TYPE,
        p_event_type IN audit_log.event_type%TYPE
    ) IS PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log (player_id, game_id, event_type)
        VALUES (p_player_id, p_game_id, SUBSTR(p_event_type, 1, 100));
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN NULL; -- Ошибки логирования игнорируем
    END p_audit_log;

    PROCEDURE p_update_ratings(
        p_game_id IN games.game_id%TYPE
    ) IS
    BEGIN
        -- TODO: Реализовать логику обновления Elo/статистики
        NULL;
    END p_update_ratings;

    --------------------------------------------------------------------------------

    PROCEDURE p_process_move(
        p_game_id        IN NUMBER,
        p_move_notation  IN VARCHAR2,
        p_player_id      IN NUMBER, -- Теперь может быть NULL, если это ИИ
        p_status_message OUT VARCHAR2
    ) IS
        v_game              games%ROWTYPE;
        v_rule              game_rules%ROWTYPE;
        v_player_color      CHAR(1);
        v_all_legal_moves   t_move_list;
        v_chosen_move       r_move;
        v_is_move_valid     BOOLEAN := FALSE;
        v_decoded_board     games.board_position%TYPE;
        v_new_board_decoded games.board_position%TYPE;
        v_new_board_encoded games.board_position%TYPE;
        v_move_count        NUMBER;
        
        -- [ИЗМЕНЕНИЕ 1] Увеличен размер для подсказок об обязательном взятии
        v_error_msg         VARCHAR2(2000); 
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;

        v_decoded_board := decode_board(v_game.board_position);

        -- [ИЗМЕНЕНИЕ] Определяем цвет игрока (даже если ID = NULL)
        IF v_game.ai_difficulty IS NOT NULL THEN
            v_player_color := v_game.current_turn;
        ELSE
            IF v_game.player_white_id = p_player_id THEN
                v_player_color := 'W';
            ELSE
                v_player_color := 'B';
            END IF;
        END IF;

        -- ... (проверка наличия ходов, поиск v_chosen_move) ...
        v_all_legal_moves := find_all_player_moves(v_decoded_board, v_player_color, v_game.rule_id);

        IF v_all_legal_moves.COUNT = 0 THEN
            UPDATE games
            SET status           = 'V',
                end_time         = SYSTIMESTAMP,
                -- Победитель - оппонент. Если оппонент ИИ, winner_id будет NULL.
                winner_player_id = CASE v_player_color WHEN 'W' THEN v_game.player_black_id ELSE v_game.player_white_id END
            WHERE game_id = p_game_id;
            p_status_message := 'Ходов нет. Вы проиграли!';
            p_update_ratings(p_game_id); -- Обновляем рейтинг
            COMMIT;
            RETURN;
        END IF;
        
        -- ... (логика валидации p_move_notation ... остается без изменений) ...
        FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
            DECLARE
                v_legal_move r_move := v_all_legal_moves(i);
                v_notation   VARCHAR2(50);
            BEGIN
                v_notation := idx_to_notation(v_legal_move.path(1).start_idx);
                FOR j IN 1 .. v_legal_move.path.COUNT LOOP
                    v_notation := v_notation || CASE v_legal_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_legal_move.path(j).end_idx);
                END LOOP;
                
                IF REPLACE(LOWER(p_move_notation), 'x', ':') = v_notation THEN
                    v_chosen_move   := v_legal_move;
                    v_is_move_valid := TRUE;
                    EXIT;
                END IF;
            END;
        END LOOP;

        -- [ИЗМЕНЕНИЕ 2] Возвращена логика подсказки об обязательном взятии
        IF NOT v_is_move_valid THEN
            
            -- Проверяем, была ли причина в пропущенном взятии
            -- (find_all_player_moves вернет *только* взятия, если они есть)
            IF v_all_legal_moves.COUNT > 0 AND v_all_legal_moves(1).is_capture = 'Y' THEN
                -- Собираем сообщение-подсказку
                DECLARE
                    v_notation_str VARCHAR2(100);
                BEGIN
                    v_error_msg := 'Неверный ход. Взятие обязательно! Доступные варианты: ';
                    FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
                        v_notation_str := idx_to_notation(v_all_legal_moves(i).path(1).start_idx);
                        FOR j IN 1 .. v_all_legal_moves(i).path.COUNT LOOP
                            v_notation_str := v_notation_str || CASE v_all_legal_moves(i).is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_all_legal_moves(i).path(j).end_idx);
                        END LOOP;
                        
                        -- Добавляем, пока помещается в v_error_msg
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
                -- Это был просто нелегальный ход, не связанный с пропуском взятия
                v_error_msg := 'Нелегальный ход: "' || p_move_notation || '".';
            END IF;

            -- Стандартная обработка ошибки (аудит, вывод, возврат)
            p_audit_log(
                p_player_id  => p_player_id,
                p_game_id    => p_game_id,
                p_event_type => SUBSTR(v_error_msg, 1, 100) -- p_audit_log сам обрежет
            );
            
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            
            p_status_message := v_error_msg;
            ROLLBACK; -- Отменяем транзакцию (т.к. был SELECT FOR UPDATE)
            RETURN;
        END IF;


        -- ... (логика применения хода к v_new_board_decoded ... ) ...
        v_new_board_decoded := v_decoded_board;
        DECLARE
            v_moving_piece        CHAR(1) := SUBSTR(v_new_board_decoded, v_chosen_move.path(1).start_idx, 1);
            v_start_pos           PLS_INTEGER := v_chosen_move.path(1).start_idx;
            v_end_pos             PLS_INTEGER := v_chosen_move.path(v_chosen_move.path.LAST).end_idx;
            v_promoted            BOOLEAN := FALSE;
        BEGIN
            v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_start_pos + 1);
            IF v_chosen_move.is_capture = 'Y' THEN
                FOR i IN 1 .. v_chosen_move.path.COUNT LOOP
                    v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_chosen_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_chosen_move.path(i).captured_idx + 1);
                END LOOP;
            END IF;
            -- ... (логика превращения в дамку) ...
            IF v_moving_piece IN (c_white_man, c_black_man) THEN
                -- ... (проверка на v_promoted) ...
                DECLARE
                    v_end_row                   PLS_INTEGER := g_board_map(idx_to_notation(v_end_pos)).row_num;
                    v_is_final_square_promotion BOOLEAN := (v_player_color = 'W' AND v_end_row = 8) OR (v_player_color = 'B' AND v_end_row = 1);
                BEGIN
                    IF v_promoted OR v_is_final_square_promotion THEN
                        v_moving_piece := CASE v_player_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                    END IF;
                END;
            END IF;
            v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board_decoded, v_end_pos + 1);
        END;

        v_new_board_encoded := encode_board(v_new_board_decoded);
        SELECT COUNT(*) + 1 INTO v_move_count FROM game_moves WHERE game_id = p_game_id;

        -- Обновляем игру
        UPDATE games
        SET board_position      = v_new_board_encoded,
            current_turn        = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            last_move_at        = SYSTIMESTAMP,
            moves_since_capture = CASE v_chosen_move.is_capture WHEN 'Y' THEN 0 ELSE v_game.moves_since_capture + 1 END,
            draw_offer_status   = NULL, -- [НОВОЕ] Любой ход отменяет предложение ничьей
            draw_offered_by     = NULL,
            draw_offered_at     = NULL
        WHERE game_id = p_game_id;

        -- Записываем ход. p_player_id будет NULL, если это ИИ.
        INSERT INTO game_moves (game_id, move_number, player_id, move_notation, is_capture, board_position)
        VALUES (p_game_id, v_move_count, p_player_id, p_move_notation, v_chosen_move.is_capture, v_new_board_encoded);
        
        -- [ИЗМЕНЕНИЕ] Проверяем p_player_id через IS NULL
        IF p_player_id IS NULL THEN
            p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
        ELSE
            p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
        END IF;

        -- ... (Проверка на конец игры: нет фигур, нет ходов, ничья по N ходов, ничья по повторению) ...
        DECLARE
            v_next_turn_color     CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
            v_next_player_moves   t_move_list;
            v_opponent_pieces_exist BOOLEAN := FALSE;
            v_repetition_count    NUMBER;
        BEGIN
            -- Проверка "У противника не осталось фигур"
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
                UPDATE games SET status = 'V', end_time = SYSTIMESTAMP, winner_player_id = p_player_id WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Победа! У противника не осталось фигур.';
                p_audit_log(p_player_id, p_game_id, 'WIN_NO_PIECES');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;

            -- Проверка "Противник заблокирован (пат)"
            v_next_player_moves := find_all_player_moves(v_new_board_decoded, v_next_turn_color, v_game.rule_id);
            IF v_next_player_moves.COUNT = 0 THEN
                UPDATE games SET status = 'V', end_time = SYSTIMESTAMP, winner_player_id = p_player_id WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Победа! Противник заблокирован.';
                p_audit_log(p_player_id, p_game_id, 'WIN_PAT');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;

            -- Проверка "Ничья по N ходов без взятия"
            -- [ИЗМЕНЕНИЕ] Используем v_game.draw_moves_limit вместо v_rule.draw_moves_limit
            IF v_game.draw_moves_limit IS NOT NULL AND v_chosen_move.is_capture = 'N' AND (v_game.moves_since_capture + 1) >= v_game.draw_moves_limit THEN
                UPDATE games SET status = 'D', end_time = SYSTIMESTAMP WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия.';
                p_audit_log(NULL, p_game_id, 'DRAW_MOVES_LIMIT');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;

            -- Проверка "Ничья по троекратному повторению"
            -- [ИЗМЕНЕНИЕ] Используем v_game.enable_pos_repetition_draw
            IF v_game.enable_pos_repetition_draw = 'Y' THEN
                SELECT COUNT(*) INTO v_repetition_count FROM game_moves WHERE game_id = p_game_id AND board_position = v_new_board_encoded;
                IF v_repetition_count >= 2 THEN -- (Позиция была 2 раза, стала 3-й)
                    UPDATE games SET status = 'D', end_time = SYSTIMESTAMP WHERE game_id = p_game_id;
                    p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.';
                    p_audit_log(NULL, p_game_id, 'DRAW_REPETITION');
                    p_update_ratings(p_game_id);
                    COMMIT;
                    RETURN;
                END IF;
            END IF;
        END;
        
        COMMIT;
    END p_process_move;

    --------------------------------------------------------------------------------

    /**
     * @function get_ai_move
     * @brief Главная точка входа для ИИ.
     * [БЕЗ ИЗМЕНЕНИЙ В ЛОГИКЕ, ТОЛЬКО В ВЫЗЫВАЮЩЕМ КОДЕ]
     */
    FUNCTION get_ai_move(
        p_board_position IN games.board_position%TYPE,
        p_ai_color       IN games.current_turn%TYPE,
        p_rule_id        IN games.rule_id%TYPE,
        p_difficulty     IN games.ai_difficulty%TYPE
    ) RETURN VARCHAR2 IS
        v_best_move_str  VARCHAR2(50);
        v_chosen_move    r_move;
        v_decoded_board  games.board_position%TYPE := decode_board(p_board_position);
        v_search_depth   PLS_INTEGER;
        v_minimax_result r_minimax_result;
        v_alpha          NUMBER;
        v_beta           NUMBER;
    BEGIN
        v_search_depth := CASE p_difficulty
                              WHEN 'E' THEN 4
                              WHEN 'M' THEN 8
                              WHEN 'H' THEN 12
                              ELSE 2
                          END;
        v_alpha := -99999;
        v_beta  := 99999;

        v_minimax_result := minimax(v_decoded_board, v_search_depth, v_alpha, v_beta, TRUE, p_ai_color, p_difficulty);
        v_chosen_move := v_minimax_result.move;

        -- ... (логика случайного хода для p_difficulty = 0) ...
        IF p_difficulty = 0 AND DBMS_RANDOM.VALUE < 0.25 THEN
             DECLARE
                 v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
             BEGIN
                 IF v_random_moves.COUNT > 0 THEN
                     v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
                 END IF;
             END;
         END IF;

        -- ... (логика формирования нотации) ...
        IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
             v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx);
             FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
                 v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_chosen_move.path(j).end_idx);
             END LOOP;
        ELSE
            -- ... (Fallback, если minimax ничего не вернул) ...
             DECLARE
                 v_fallback_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
             BEGIN
                  IF v_fallback_moves.COUNT > 0 THEN
                      v_chosen_move := v_fallback_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_fallback_moves.COUNT + 1)));
                      v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx);
                      FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
                          v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_chosen_move.path(j).end_idx);
                      END LOOP;
                  ELSE
                      v_best_move_str := NULL;
                  END IF;
             END;
        END IF;

        RETURN v_best_move_str;
    END get_ai_move;
    
    --------------------------------------------------------------------------------

    PROCEDURE create_game(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_ai_difficulty       IN CHAR     DEFAULT NULL,
        p_player_color        IN CHAR     DEFAULT NULL,
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
        p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
        p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'
    ) IS
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_initial_position    games.board_position%TYPE;
        v_encoded_position    games.board_position%TYPE;
        v_status              games.status%TYPE;
        v_ai_move             VARCHAR2(50);
        v_ai_msg              VARCHAR2(1000);
        v_game_id             NUMBER;
        v_status_message      VARCHAR2(1000);
        v_my_active_game_id   NUMBER;
        v_error_msg           VARCHAR2(255);
    BEGIN
        v_current_player_id := get_or_create_player_id(v_current_username);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_current_player_id;

        -- Проверка, не занят ли игрок
        v_my_active_game_id := get_active_game(v_current_player_id);
        IF v_my_active_game_id IS NOT NULL THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id;
            p_audit_log(v_current_player_id, v_my_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- [ИЗМЕНЕНИЕ] Проверка на конфликт параметров
        IF p_opponent_username IS NOT NULL AND p_ai_difficulty IS NOT NULL THEN
            v_error_msg := 'Нельзя одновременно указать оппонента (' || p_opponent_username || ') и сложность ИИ.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        -- Определение цвета
        DECLARE
            v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
        BEGIN
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

        -- [ИЗМЕНЕНИЕ] Логика создания игры PvE
        IF p_ai_difficulty IS NOT NULL THEN
            v_status := 'A';
            -- ID второго игрока (ИИ) остается NULL
            IF v_white_player_id IS NULL THEN
                v_white_player_id := NULL; -- ИИ играет за белых
            ELSE
                v_black_player_id := NULL; -- ИИ играет за черных
            END IF;

            INSERT INTO games (
                creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn,
                board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                v_encoded_position, p_ai_difficulty, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Игра против ИИ создана (ID: ' || v_game_id || '). Вы играете за ' || CASE WHEN v_white_player_id = v_current_player_id THEN 'белых (W)' ELSE 'черных (B)' END || '.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_PVE_GAME');

            IF v_white_player_id IS NULL THEN
                v_ai_move := get_ai_move(v_initial_position, 'W', p_rule_id, p_ai_difficulty);
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg); -- ID ИИ = NULL
                    v_status_message := v_status_message || ' ИИ начинает с хода: ' || v_ai_move;
                END IF;
            END IF;
        
        -- [ИЗМЕНЕНИЕ] Логика создания PvP
        ELSIF p_opponent_username IS NOT NULL THEN
        -- Проверка на игру с самим собой
            IF v_current_username = UPPER(p_opponent_username) THEN 
                v_error_msg := 'Нельзя вызвать самого себя.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

            -- Проверка, не занят ли оппонент
            DECLARE
            v_active_game_count NUMBER;
            BEGIN
            v_active_game_count := get_active_game(v_opponent_player_id);
            
                -- Проверка занятости оппонента
                IF v_active_game_count > 0 THEN
                    v_error_msg := 'Игрок "' || p_opponent_username || '" уже занят в другой партии (ID: '|| v_active_game_count ||').';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
            END;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
            v_status := 'C'; -- Challenged

            INSERT INTO games (
                creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn,
                board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                v_encoded_position, NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_CHALLENGE');
            
        -- [ИЗМЕНЕНИЕ] Логика создания открытой игры
        ELSE
            v_status := 'O'; -- Open
            INSERT INTO games (
                creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn,
                board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                v_encoded_position, NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_OPEN_GAME');
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE(v_status_message);
        
        -- Вывод доски, если ИИ сделал первый ход
        IF p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL THEN
             BEGIN
                 print_board(p_game_id => v_game_id, p_hide_header => TRUE);
             EXCEPTION
                 WHEN OTHERS THEN NULL;
             END;
         END IF;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END create_game;

    --------------------------------------------------------------------------------

    PROCEDURE join_game(p_game_id IN NUMBER) IS
        v_game       games%ROWTYPE;
        v_player_id  players.player_id%TYPE;
        v_active_game_id NUMBER;
        v_error_msg    VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;

        v_active_game_id := get_active_game(v_player_id);

        IF v_active_game_id IS NOT NULL THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

    -- Блок try-catch на случай, если игра не найдена
        BEGIN
            SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;

        IF v_game.status = 'C' THEN -- Принятие прямого вызова
            IF NOT (v_player_id IN (v_game.player_white_id, v_game.player_black_id) AND v_player_id != v_game.creator_player_id) THEN
                v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK; -- Нужен, т.к. был SELECT FOR UPDATE
                RETURN;
            END IF;
        ELSIF v_game.status = 'O' THEN -- Присоединение к открытой игре
            -- [ИЗМЕНЕНИЕ 3] Замена e_invalid_opponent
            IF v_player_id = v_game.creator_player_id THEN
                v_error_msg := 'Нельзя присоединиться к собственной открытой игре (ID: ' || p_game_id || ').';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK; -- Нужен, т.к. был SELECT FOR UPDATE
                RETURN;
            END IF;
        ELSE
            v_error_msg := 'Нельзя присоединиться к этой игре (ID: ' || p_game_id || ', статус: '|| v_game.status || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK; -- Нужен, т.к. был SELECT FOR UPDATE
            RETURN;
        END IF;
        
        -- Если игра 'O', вписываем ID игрока в пустой слот
        IF v_game.status = 'O' THEN
            UPDATE games
            SET player_white_id = NVL(v_game.player_white_id, v_player_id),
                player_black_id = NVL(v_game.player_black_id, v_player_id),
                status          = 'A',
                start_time      = SYSTIMESTAMP,
                last_move_at    = SYSTIMESTAMP -- Сбрасываем таймер
            WHERE game_id = p_game_id;
        ELSE -- 'C'
            UPDATE games
            SET status       = 'A',
                start_time   = SYSTIMESTAMP,
                last_move_at = SYSTIMESTAMP
            WHERE game_id = p_game_id;
        END IF;
        
        p_audit_log(v_player_id, p_game_id, 'JOIN_GAME');
        DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
        COMMIT;
    EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при присоединении к игре: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 100));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
    END join_game;
    
    --------------------------------------------------------------------------------

    PROCEDURE resign_game IS
        v_game      games%ROWTYPE;
        v_player_id players.player_id%TYPE;
        v_game_id   NUMBER;
        v_winner_id players.player_id%TYPE; -- Может быть NULL, если ИИ
        v_error_msg VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;
        v_game_id   := get_active_game(v_player_id);

        IF v_game_id IS NULL THEN
            v_error_msg := 'У вас нет активной партии, чтобы сдаться.';
            p_audit_log(v_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

        -- [ИЗМЕНЕНИЕ] Разделение логики. Эта процедура - только для 'A'
        IF v_game.status != 'A' THEN
            v_error_msg := 'Эта партия (ID: ' || v_game_id || ') неактивна (статус '||v_game.status||'). Используйте cancel_game для отмены вызова.';
            p_audit_log(v_player_id, v_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK; -- Нужен, т.к. был SELECT FOR UPDATE
            RETURN;
        END IF;

        DECLARE
            v_winner_username players.username%TYPE;
        BEGIN
            -- Определяем победителя. Он может быть NULL, если это ИИ.
            IF v_player_id = v_game.player_white_id THEN
                v_winner_id := v_game.player_black_id;
            ELSE
                v_winner_id := v_game.player_white_id;
            END IF;

            UPDATE games
            SET status           = 'R', -- Resigned
                winner_player_id = v_winner_id,
                end_time         = SYSTIMESTAMP
            WHERE game_id = v_game_id;

            IF v_winner_id IS NOT NULL THEN
                SELECT username INTO v_winner_username FROM players WHERE player_id = v_winner_id;
            ELSE
                v_winner_username := 'AI (Server)';
            END IF;
            
            p_audit_log(v_player_id, v_game_id, 'RESIGN_GAME');
            p_update_ratings(v_game_id);
            DBMS_OUTPUT.PUT_LINE('[OK] Вы сдались в партии ' || v_game_id || '. Победитель: ' || v_winner_username || '.');
        END;
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END resign_game;

    --------------------------------------------------------------------------------
   
    FUNCTION f_get_board_as_clob(
        p_board_position    IN VARCHAR2,
        p_highlight_indices IN t_map_indices DEFAULT t_map_indices()
    ) RETURN CLOB IS
        v_clob          CLOB;
        v_char          CHAR(1);
        v_linear_idx    PLS_INTEGER;
        v_decoded_board VARCHAR2(100) := p_board_position; -- ДЕКОДИРОВАНИЕ
        c_nl CONSTANT   VARCHAR2(1) := CHR(10);
    BEGIN
        DBMS_LOB.createtemporary(v_clob, TRUE);
        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);

        FOR r IN REVERSE 1 .. 8 LOOP
            DBMS_LOB.append(v_clob, r || ' |');
            FOR c IN 1 .. 8 LOOP
                v_linear_idx := ((8 - r) * 8) + c;
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
        
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);
        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);
        RETURN v_clob;
    END f_get_board_as_clob;

    --------------------------------------------------------------------------------

    PROCEDURE start_replay_session(p_game_id IN NUMBER) IS
        v_player_id   players.player_id%TYPE;
        v_game_status games.status%TYPE;
        v_max_moves   NUMBER;
        v_seq_name    VARCHAR2(64);
        v_job_name    VARCHAR2(64);
        v_error_msg   VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;

        SELECT status INTO v_game_status FROM games WHERE game_id = p_game_id;
        IF v_game_status IN ('A', 'O', 'C') THEN
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

        v_seq_name := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id;
        v_job_name := 'DROP_REPLAY_SEQ_' || p_game_id || '_' || v_player_id;

        BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE ' || v_seq_name; EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;

        EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seq_name || ' START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE ' || v_max_moves || ' NOCYCLE NOCACHE';
        
        DBMS_SCHEDULER.create_job(
            job_name   => v_job_name,
            job_type   => 'PLSQL_BLOCK',
            job_action => 'BEGIN EXECUTE IMMEDIATE ''DROP SEQUENCE ' || v_seq_name || '''; END;',
            start_date => SYSTIMESTAMP + INTERVAL '30' MINUTE,
            enabled    => TRUE,
            auto_drop  => TRUE,
            comments   => 'Drop replay sequence for game ' || p_game_id || ' and player ' || v_player_id
        );
        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Сессия для партии с id = ' || p_game_id || ' успешно запущена. Для просмотра игры используйте процедуру show_next_replay_move');

    END start_replay_session;

    --------------------------------------------------------------------------------

    PROCEDURE show_next_replay_move(p_game_id IN NUMBER, p_moves_to_show IN NUMBER DEFAULT 1) IS
        v_player_id     players.player_id%TYPE;
        v_seq_name      VARCHAR2(64);
        v_move_num      NUMBER;
        v_color_str     VARCHAR2(30);

        -- Переменные для хранения результата игры
        v_game_rec      games%ROWTYPE;
        v_winner_name   players.username%TYPE;
        v_loser_name    players.username%TYPE;
        v_final_message VARCHAR2(250);
        v_error_msg     VARCHAR2(255);
        v_replay_finished BOOLEAN := FALSE;
        v_replay_error    BOOLEAN := FALSE;
        
        CURSOR c_game_moves (cp_game_id NUMBER, cp_move_number NUMBER) IS
            SELECT
                username,
                move_notation,
                board_position
            FROM v_game_protocol
            WHERE game_id = cp_game_id AND move_number = cp_move_number;

    BEGIN
        v_player_id := get_or_create_player_id(USER);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;
        v_seq_name  := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id;

        FOR i IN 1 .. p_moves_to_show LOOP
            BEGIN
                -- Пытаемся получить следующий номер хода из sequence
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF SQLCODE = -8004 THEN 
                            -- -8004: sequence.NEXTVAL exceeds MAXVALUE (просмотр завершен)
                            v_replay_finished := TRUE;
                        ELSE 
                            -- -2289: sequence does not exist (сессия не начата) или другая ошибка
                            v_replay_error := TRUE;
                            v_error_msg := 'Сессия просмотра не начата или прервана (ID: ' || p_game_id || '). Ошибка: ' || SQLERRM;
                            p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 100));
                            DBMS_OUTPUT.PUT_LINE(v_error_msg);
                            DBMS_OUTPUT.PUT_LINE('--[ВНИМАНИЕ] Вызовите game_logic.start_replay_session(' || p_game_id || ');');
                        END IF;
                END;

                -- [НОВАЯ ЛОГИКА] Проверяем флаги
                -- Если была ошибка (сессия не найдена), выходим из цикла
                IF v_replay_error THEN
                    EXIT;
                END IF;

                -- Если просмотр завершен, выводим финальное сообщение и выходим
                IF v_replay_finished THEN
                    BEGIN
                        SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
                        
                        IF v_game_rec.status = 'D' THEN
                            v_final_message := 'Ничья.';
                        ELSIF v_game_rec.status = 'T' THEN
                            v_final_message := 'Игра завершена по таймауту.';
                        ELSIF v_game_rec.status = 'V' THEN
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_game_rec.winner_player_id;
                            v_final_message := 'Победа игрока ' || v_winner_name || '.';
                        ELSIF v_game_rec.status = 'R' THEN
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_game_rec.winner_player_id;
                            DECLARE
                                v_loser_id players.player_id%TYPE;
                            BEGIN
                                IF v_game_rec.winner_player_id = v_game_rec.player_white_id THEN
                                    v_loser_id := v_game_rec.player_black_id;
                                ELSE
                                    v_loser_id := v_game_rec.player_white_id;
                                END IF;
                                SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id;
                                v_final_message := v_loser_name || ' сдался. Победитель: ' || v_winner_name || '.';
                            END;
                        ELSE
                            v_final_message := 'Игра завершена с неопределенным статусом.';
                        END IF;

                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_final_message := 'Игра не найдена.';
                    END;
                    
                    DBMS_OUTPUT.PUT_LINE('--[ КОНЕЦ ПАРТИИ ]-- ' || v_final_message);
                    DBMS_OUTPUT.PUT_LINE('-- Для повторного просмотра вызовите start_replay_session.');
                    
                    EXIT; -- Выходим из цикла FOR
                END IF;

                -- Если мы здесь, значит ошибка не произошла и просмотр не закончен
                -- Печатаем ход
                FOR move_rec IN c_game_moves(p_game_id, v_move_num) LOOP
                    v_color_str := CASE WHEN MOD(v_move_num, 2) = 1 THEN '(Белые)' ELSE '(Черные)' END;
                    DBMS_OUTPUT.PUT_LINE('---');
                    DBMS_OUTPUT.PUT_LINE('Ход ' || v_move_num || ' ' || RPAD(move_rec.username, 20) || ' ' || RPAD(v_color_str, 10) || ' : ' || move_rec.move_notation);
                    DBMS_OUTPUT.PUT_LINE(f_get_board_as_clob(decode_board(move_rec.board_position)));
                END LOOP;

            END;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE;
    END show_next_replay_move;
    
    --------------------------------------------------------------------------------

    PROCEDURE print_board(
        p_game_id     IN NUMBER   DEFAULT NULL,
        p_username    IN VARCHAR2 DEFAULT NULL,
        p_hide_header IN BOOLEAN  DEFAULT FALSE
    ) IS
        v_target_game_id  games.game_id%TYPE;
        v_target_user_id  players.player_id%TYPE;
        v_target_username players.username%TYPE;
        v_game            games%ROWTYPE;
        v_printable_board CLOB;
        v_status_header   VARCHAR2(200);
        v_player_username players.username%TYPE;
        v_move_count      NUMBER;
        c_nl CONSTANT VARCHAR2(1) := CHR(10);
        v_error_msg        VARCHAR2(255);
        v_viewer_player_id players.player_id%TYPE;
    BEGIN
        v_viewer_player_id := get_or_create_player_id(USER);
        
        -- [ЛОГИКА ПОИСКА И ОШИБОК]
        IF p_game_id IS NOT NULL AND p_username IS NOT NULL THEN
            v_error_msg := 'Для поиска передайте процедуре только один параметр (имя пользователя или id игры).';
            p_audit_log(v_viewer_player_id, NULL, v_error_msg);
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
                    p_audit_log(v_viewer_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
            END;
            
            -- [ИСПРАВЛЕНИЕ] Используем get_active_game
            v_target_game_id := get_active_game(v_target_user_id);
            IF v_target_game_id IS NULL THEN
                v_error_msg := 'У пользователя "' || p_username || '" не найдено активных сессий.';
                p_audit_log(v_viewer_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
        ELSE
            v_target_user_id := v_viewer_player_id; 
            -- [ИСПРАВЛЕНИЕ] Используем get_active_game
            v_target_game_id := get_active_game(v_target_user_id); 
            
            IF v_target_game_id IS NULL THEN
                v_error_msg := 'У вас нет активных игр.';
                p_audit_log(v_target_user_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
        END IF;
        
        BEGIN
            SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
                p_audit_log(v_viewer_player_id, v_target_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
        IF v_game.status NOT IN ('A', 'O', 'C') THEN
            v_error_msg := 'Игра с id = ' || v_target_game_id || ' закончена, вы можете посмотреть повтор игры.';
            p_audit_log(v_viewer_player_id, v_target_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        DECLARE
            v_active_player_id  players.player_id%TYPE;
            v_highlight_indices t_map_indices;
            v_legal_moves       t_move_list;
            v_decoded_board     games.board_position%TYPE;
            -- v_viewer_player_id уже определен во внешней области
        BEGIN
            v_decoded_board := decode_board(v_game.board_position);
            v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
            
            -- [ЛОГИКА ПОДСВЕТКИ]
            BEGIN
                IF v_game.status = 'A' AND v_viewer_player_id = v_active_player_id THEN
                    v_legal_moves := find_all_player_moves(v_decoded_board, v_game.current_turn, v_game.rule_id);
                    
                    IF v_legal_moves.COUNT > 0 AND v_legal_moves(1).is_capture = 'Y' THEN
                        -- Перебираем ВСЕ легальные ходы
                        FOR i IN 1 .. v_legal_moves.COUNT LOOP
                            -- Вложенный цикл: перебираем ВСЕ шаги в этом ходе
                            FOR j IN 1 .. v_legal_moves(i).path.COUNT LOOP
                                -- Подсвечиваем КОНЕЧНОЕ поле каждого шага ('c3', 'd5', 'f7')
                                v_highlight_indices(v_legal_moves(i).path(j).end_idx) := TRUE;
                            END LOOP;
                            
                        END LOOP;
                    END IF;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL; -- Ошибка подсветки не должна мешать печати
            END;
            -- [КОНЕЦ ЛОГИКИ ПОДСВЕТКИ]
            
            IF NOT p_hide_header THEN
                IF v_game.status = 'A' THEN
                    SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
                    
                    IF v_active_player_id IS NOT NULL THEN
                        SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
                    ELSIF v_game.ai_difficulty IS NOT NULL THEN
                        v_player_username := 'AI (Server)';
                    ELSE
                        v_player_username := '(ожидание)';
                    END IF;
                    
                    v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || v_player_username || ' (' || v_game.current_turn || ')';
                ELSE
                    v_status_header := 'Состояние доски: ' || v_game.status;
                END IF;
                DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
            END IF;

            v_printable_board := f_get_board_as_clob(v_decoded_board, v_highlight_indices);
            DBMS_OUTPUT.PUT_LINE(v_printable_board);
        END;
    END print_board;

    --------------------------------------------------------------------------------

    PROCEDURE make_move(p_move_notation IN VARCHAR2) IS
        v_game_id   NUMBER;
        v_game      games%ROWTYPE;
        v_player_id players.player_id%TYPE;
        v_human_msg VARCHAR2(1000);
        v_ai_msg    VARCHAR2(1000);
        c_nl CONSTANT VARCHAR2(1) := CHR(10);
        v_error_msg VARCHAR2(200);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        v_game_id   := get_active_game(v_player_id);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;
        IF v_game_id IS NULL THEN
            v_error_msg := 'Нет активных игр, чтобы сделать ход.';
        
            -- 1) Аудит
            p_audit_log(
                p_player_id => v_player_id, 
                p_game_id   => NULL, 
                p_event_type => v_error_msg
            );
            
            -- 2) Вывод
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            
            -- 3) Выход
            RETURN;
        END IF;

        SELECT * INTO v_game FROM games WHERE game_id = v_game_id;

        IF v_game.status <> 'A' THEN
            v_error_msg := 'Игра (ID: ' || v_game_id || ') еще не активна. Невозможно сделать ход. Противник не подключился.';
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
        IF INSTR(LOWER(v_human_msg), 'нелегальный ход') > 0 THEN
            RETURN;
        END IF;
        BEGIN
            print_board(p_game_id => v_game_id, p_hide_header => TRUE);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        
        -- Ход ИИ (если применимо)
        DECLARE
            v_next_game_state games%ROWTYPE;
            v_ai_move         VARCHAR2(50);
        BEGIN
            SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;

            -- [ИЗМЕНЕНИЕ] Проверка на ИИ через ai_difficulty и IS NULL
            IF v_next_game_state.status = 'A' AND v_next_game_state.ai_difficulty IS NOT NULL AND
               ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id IS NULL) OR
                (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id IS NULL))
            THEN
                v_ai_move := get_ai_move(v_next_game_state.board_position, v_next_game_state.current_turn, v_next_game_state.rule_id, v_next_game_state.ai_difficulty);

                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg); -- ID ИИ = NULL
                    DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                    BEGIN
                        print_board(p_game_id => v_game_id, p_hide_header => TRUE);
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
    
    PROCEDURE cancel_game IS
        v_game_id   NUMBER; -- [ИЗМЕНЕНИЕ] Убрана инициализация из параметра
        v_player_id players.player_id%TYPE;
        v_game      games%ROWTYPE;
        v_error_msg VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;
        v_game_id := get_active_game(v_player_id);
        
        IF v_game_id IS NULL THEN
            v_error_msg := 'Нет активных игр или вызовов для отмены.';
            p_audit_log(v_player_id, NULL, v_error_msg); 
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
      
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

        -- Проверка статуса (только 'O' или 'C')
        IF v_game.status NOT IN ('O', 'C') THEN
            v_error_msg := 'Эту игру (ID: ' || v_game_id || ') нельзя отменить (статус '||v_game.status||'). Используйте resign_game, чтобы сдаться.';
            p_audit_log(v_player_id, v_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK; -- Нужен, т.к. был SELECT FOR UPDATE
            RETURN;
        END IF;
               
        DELETE FROM games WHERE game_id = v_game_id;
        p_audit_log(v_player_id, v_game_id, 'CANCEL_GAME');
        DBMS_OUTPUT.PUT_LINE('Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
        COMMIT;
    EXCEPTION
        -- Общий обработчик
        WHEN OTHERS THEN
            v_error_msg := 'Неожиданная ошибка при отмене игры: ' || SQLERRM;
            p_audit_log(v_player_id, v_game_id, SUBSTR(v_error_msg, 1, 100));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
    END cancel_game;

    --------------------------------------------------------------------------------
    -- =========================================================================
    -- НОВЫЕ ЗАГЛУШКИ (STUBS)
    -- =========================================================================

    PROCEDURE offer_draw IS
    BEGIN
        -- TODO:
        -- 1. Найти активную игру (get_active_game)
        -- 2. Проверить, что статус 'A'
        -- 3. Проверить, что сейчас *не* твой ход (или по правилам)
        -- 4. UPDATE games SET draw_offered_by = v_player_id, draw_offer_status = 'O', draw_offered_at = SYSTIMESTAMP
        RAISE_APPLICATION_ERROR(-50000, 'Функция offer_draw еще не реализована.');
    END offer_draw;
    
    PROCEDURE accept_draw IS
    BEGIN
        -- TODO:
        -- 1. Найти активную игру
        -- 2. Проверить, что статус 'A'
        -- 3. Проверить, что draw_offer_status = 'O' и draw_offered_by != v_player_id
        -- 4. UPDATE games SET status = 'D', end_time = SYSTIMESTAMP, ...
        -- 5. p_audit_log
        -- 6. p_update_ratings
        RAISE_APPLICATION_ERROR(-50000, 'Функция accept_draw еще не реализована.');
    END accept_draw;
    
    PROCEDURE cancel_draw_offer IS
    BEGIN
        -- TODO:
        -- 1. Найти активную игру
        -- 2. Проверить, что draw_offer_status = 'O' и draw_offered_by != v_player_id
        -- 3. UPDATE games SET draw_offer_status = 'D'
        RAISE_APPLICATION_ERROR(-50000, 'Функция cancel_draw_offer еще не реализована.');
    END cancel_draw_offer;

    --------------------------------------------------------------------------------

    PROCEDURE create_match(
        p_opponent_username IN VARCHAR2,
        p_games_to_win      IN NUMBER,
        p_rule_id           IN NUMBER DEFAULT 1
    ) IS
    BEGIN
        -- TODO:
        -- 1. Проверить p_games_to_win > 0
        -- 2. Найти ID (get_or_create_player_id)
        -- 3. Проверить, что оба игрока не заняты
        -- 4. INSERT INTO matches (...)
        RAISE_APPLICATION_ERROR(-50000, 'Функция create_match еще не реализована.');
    END create_match;

    PROCEDURE join_match IS
    BEGIN
        -- TODO:
        -- 1. Найти активный матч игрока
        -- 2. UPDATE matches SET status = 'C', winner_player_id = opponent_id
        -- 3. Отменить текущую активную игру (если есть)
        RAISE_APPLICATION_ERROR(-50000, 'Функция join_match еще не реализована.');
    END join_match;

    PROCEDURE resign_match IS
    BEGIN
        -- TODO:
        -- 1. Найти активный матч игрока
        -- 2. UPDATE matches SET status = 'C', winner_player_id = opponent_id
        -- 3. Отменить текущую активную игру (если есть)
        RAISE_APPLICATION_ERROR(-50000, 'Функция resign_match еще не реализована.');
    END resign_match;

    PROCEDURE cancel_match IS
    BEGIN
        -- TODO:
        -- 1. Найти матч игрока со статусом 'S' (Scheduled)
        -- 2. DELETE FROM matches WHERE match_id = ...
        RAISE_APPLICATION_ERROR(-50000, 'Функция cancel_match еще не реализована.');
    END cancel_match;


    --------------------------------------------------------------------------------
    -- ЗАГЛУШКИ ДЛЯ ЗАДАЧ (PUZZLES)
    --------------------------------------------------------------------------------
    PROCEDURE start_puzzle(p_puzzle_id IN NUMBER) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция start_puzzle еще не реализована.');
    END start_puzzle;
    
    PROCEDURE make_puzzle_move(p_move_notation IN VARCHAR2) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция make_puzzle_move еще не реализована.');
    END make_puzzle_move;
    
    PROCEDURE create_puzzle(p_board_position IN VARCHAR2, p_turn_to_move IN CHAR, p_moves_to_solve IN NUMBER DEFAULT NULL, p_difficulty_level IN NUMBER) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция create_puzzle еще не реализована.');
    END create_puzzle;
    
    PROCEDURE show_puzzles(p_difficulty IN NUMBER DEFAULT NULL) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция show_puzzles еще не реализована.');
    END show_puzzles;
    
    PROCEDURE show_my_puzzles IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция show_my_puzzles еще не реализована.');
    END show_my_puzzles;
    
    PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция delete_my_puzzle еще не реализована.');
    END delete_my_puzzle;
    
    PROCEDURE show_daily_puzzle(p_date_str IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция show_daily_puzzle еще не реализована.');
    END show_daily_puzzle;
    
    PROCEDURE start_daily_puzzle IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция start_daily_puzzle еще не реализована.');
    END start_daily_puzzle;
    
    PROCEDURE print_puzzle_board IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция print_puzzle_board еще не реализована.');
    END print_puzzle_board;
    
    PROCEDURE quit_puzzle_attempt IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция quit_puzzle_attempt еще не реализована.');
    END quit_puzzle_attempt;

    PROCEDURE info IS
    BEGIN
        RAISE_APPLICATION_ERROR(-50000, 'Функция INFO еще не реализована.');
    END info;


     
--------------------------------------------------------------------------------
BEGIN -- Package Initialization Block
    -- Больше нет нужды в статической инициализации.
    -- Карта будет создаваться "на лету" при первом вызове.
    NULL;
END game_logic;