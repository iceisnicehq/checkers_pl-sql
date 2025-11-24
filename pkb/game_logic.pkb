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

    /**
     * @function get_active_game
     * @brief (ИЗМЕНЕНО) Находит ЛЮБУЮ активную сессию (игру ИЛИ просмотр).
     * @return game_id, если игрок занят (играет или смотрит), иначе NULL.
     */
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
        p_board   IN VARCHAR2,
        p_color   IN CHAR,
        p_rule_id IN NUMBER -- [ИЗМЕНЕНИЕ] Этот параметр КРИТИЧЕСКИ необходим
    ) RETURN t_move_list IS
        v_moves t_move_list;
        v_temp  r_move; -- A temporary record for swapping
    BEGIN
        -- [ИЗМЕНЕНИЕ] Вызываем find_all_player_moves с p_rule_id, а не '1'
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

    --------------------------------------------------------------------------------
    
    
    /**
     * @function evaluate_board
     * @brief Assigns a numerical score to a given board position.
     * Positive scores favor the AI, negative scores favor the opponent.
     */
    FUNCTION evaluate_board(
        p_board      IN VARCHAR2,
        p_ai_color   IN CHAR,
        p_difficulty IN NUMBER
    ) RETURN NUMBER IS
        v_score         NUMBER := 0;
        v_piece         CHAR(1);
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные
        v_total_squares PLS_INTEGER;
        v_board_size    PLS_INTEGER;
        
        -- Weights for pieces and positions (остаются без изменений)
        c_man_value     CONSTANT NUMBER := 10;
        c_king_value    CONSTANT NUMBER := 50;
        c_side_val      CONSTANT NUMBER := 20; 
        c_wall_val      CONSTANT NUMBER := 10; 

    BEGIN
        -- [ИЗМЕНЕНИЕ] Определяем размер доски "на лету"
        v_total_squares := LENGTH(p_board);
        v_board_size    := SQRT(v_total_squares);
        
        -- [ИЗМЕНЕНИЕ] Убеждаемся, что кэш карт (g_map_*) готов
        p_init_board_map(v_board_size);
    
        -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
        FOR i IN 1..v_total_squares LOOP
            v_piece := SUBSTR(p_board, i, 1);
            IF v_piece != c_empty_field THEN
                DECLARE
                    v_piece_value    NUMBER;
                    v_multiplier     NUMBER;
                    v_piece_color    CHAR(1);
                    
                    -- [ИЗМЕНЕНИЕ] Получаем v_row и v_col из кэша
                    v_field_rec      rec_board_field := g_map_by_idx(i);
                    v_row            PLS_INTEGER     := v_field_rec.row_num;
                    v_col            PLS_INTEGER     := v_field_rec.col_num;
                    
                    v_position_bonus NUMBER := 0;
                BEGIN
                    -- 1. Determine piece ownership and value
                    v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                    v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                    v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                    
                    -- Add the basic material score
                    v_score := v_score + (v_piece_value * v_multiplier);

                    -- 2. Calculate and add positional bonuses
                    IF p_difficulty < 2 THEN
                        -- [ИЗМЕНЕНИЕ] Бонус за борт (1 или 8 -> 1 или v_board_size)
                        IF v_col = 1 OR v_col = v_board_size THEN
                            v_position_bonus := v_position_bonus + c_side_val;
                        END IF;

                        -- [ИЗМЕНЕНИЕ] Бонус за продвижение
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
        
        -- Check for terminal win/loss state
        DECLARE
            v_ai_pieces    PLS_INTEGER := 0;
            v_opp_pieces   PLS_INTEGER := 0;
        BEGIN
            -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
            FOR k IN 1..v_total_squares LOOP
                IF SUBSTR(p_board, k, 1) != c_empty_field THEN
                    IF (CASE WHEN SUBSTR(p_board, k, 1) IN ('w', 'W') THEN 'W' ELSE 'B' END) = p_ai_color THEN
                        v_ai_pieces := 1;
                    ELSE
                        v_opp_pieces := 1;
                    END IF;
                END IF;
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

    ---------------------------------------------------------------------------------

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
        v_new_board    VARCHAR2(200) := p_board; -- [ИЗМЕНЕНИЕ] Увеличен размер
        v_moving_piece CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
        v_start_pos    PLS_INTEGER := p_move.path(1).start_idx;
        v_end_pos      PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
        v_promoted     BOOLEAN := FALSE;
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные
        v_total_squares PLS_INTEGER;
        v_board_size    PLS_INTEGER;
    BEGIN
        -- [ИЗМЕНЕНИЕ] Определяем размер доски и инициализируем кэш
        v_total_squares := LENGTH(p_board);
        v_board_size    := SQRT(v_total_squares);
        p_init_board_map(v_board_size);
    
        -- Логика очистки старой позиции (без изменений)
        v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

        -- Логика очистки срубленных шашек (без изменений)
        IF p_move.is_capture = 'Y' THEN
            FOR i IN 1..p_move.path.COUNT LOOP
                v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
            END LOOP;
        END IF;

        -- Логика превращения в "дамку"
        IF v_moving_piece IN (c_white_man, c_black_man) THEN
            DECLARE
                -- [ИЗМЕНЕНИЕ] Получаем v_end_row из нового кэша
                v_end_row PLS_INTEGER := g_map_by_idx(v_end_pos).row_num;
                -- [ИЗМЕНЕНИЕ] v_end_row = 8 заменено на v_end_row = v_board_size
                v_is_promotion BOOLEAN := (p_color = 'W' AND v_end_row = v_board_size) OR (p_color = 'B' AND v_end_row = 1);
            BEGIN
                IF v_is_promotion THEN
                    v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                END IF;
            END;
        END IF;

        -- Логика установки новой позиции (без изменений)
        v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
        RETURN v_new_board;
        
    EXCEPTION
        -- [ИЗМЕНЕНИЕ] Добавлен обработчик ошибок на случай сбоя кэша
        WHEN OTHERS THEN
            p_audit_log(NULL, NULL, 'apply_move_to_board: Ошибка ' || SQLERRM);
            RETURN p_board; -- Возвращаем исходную доску в случае сбоя
    END apply_move_to_board;


    /**
     * @function minimax
     * @brief The core recursive Minimax algorithm with Alpha-Beta Pruning.
     */
FUNCTION minimax(
        p_board         IN VARCHAR2,
        p_depth         IN PLS_INTEGER,
        p_alpha         IN NUMBER, 
        p_beta          IN NUMBER, 
        p_is_maximizing IN BOOLEAN,
        p_ai_color      IN CHAR,
        p_difficulty    IN NUMBER,
        p_rule_id       IN NUMBER  -- [ИЗМЕНЕНИЕ] Добавлен p_rule_id
    ) RETURN r_minimax_result IS
        v_result r_minimax_result;
        v_possible_moves t_move_list; 
        v_current_color  CHAR(1);
        v_local_alpha    NUMBER := p_alpha;
        v_local_beta     NUMBER := p_beta;
    BEGIN
        v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;
        
        -- [ИЗМЕНЕНИЕ] Передаем p_rule_id в get_sorted_possible_moves
        v_possible_moves := get_sorted_possible_moves(
            p_board   => p_board, 
            p_color   => v_current_color, 
            p_rule_id => p_rule_id
        );

        IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN
            -- Вызов evaluate_board не меняется, так как p_difficulty все еще используется
            v_result.score := evaluate_board(p_board, p_ai_color, p_difficulty);
            v_result.move := NULL;
            RETURN v_result;
        END IF;
        
        IF p_is_maximizing THEN
            v_result.score := -99999; 
            FOR i IN 1..v_possible_moves.COUNT LOOP
                DECLARE
                    v_new_board   VARCHAR2(200) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                    v_eval_result r_minimax_result;
                BEGIN
                    -- [ИЗМЕНЕНИЕ] Передаем p_rule_id в рекурсивный вызов
                    v_eval_result := minimax(
                        p_board         => v_new_board, 
                        p_depth         => p_depth - 1, 
                        p_alpha         => v_local_alpha, 
                        p_beta          => v_local_beta, 
                        p_is_maximizing => FALSE, 
                        p_ai_color      => p_ai_color, 
                        p_difficulty    => p_difficulty,
                        p_rule_id       => p_rule_id -- <-- Передаем
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
                    v_new_board   VARCHAR2(200) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                    v_eval_result r_minimax_result;
                BEGIN
                    -- [ИЗМЕНЕНИЕ] Передаем p_rule_id в рекурсивный вызов
                    v_eval_result := minimax(
                        p_board         => v_new_board, 
                        p_depth         => p_depth - 1, 
                        p_alpha         => v_local_alpha, 
                        p_beta          => v_local_beta, 
                        p_is_maximizing => TRUE, 
                        p_ai_color      => p_ai_color, 
                        p_difficulty    => p_difficulty,
                        p_rule_id       => p_rule_id -- <-- Передаем
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

    -- =========================================================================
    -- БЛОК ПРОЦЕДУР 
    -- =========================================================================
    PROCEDURE p_audit_log(
        p_player_id  IN players.player_id%TYPE,
        p_game_id    IN games.game_id%TYPE,
        p_event_msg  IN audit_log.event_msg%TYPE -- [ИЗМЕНЕНИЕ] event_type -> event_msg
    ) IS PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_log (
            player_id, 
            game_id, 
            event_msg -- [ИЗМЕНЕНИЕ] event_type -> event_msg
        )
        VALUES (
            p_player_id, 
            p_game_id, 
            SUBSTR(p_event_msg, 1, 255) -- [ИЗМЕНЕНИЕ] Увеличено до лимита (255)
        );
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
        v_player_color      CHAR(1);
        v_all_legal_moves   t_move_list;
        v_chosen_move       r_move;
        v_is_move_valid     BOOLEAN := FALSE;
        v_move_count        NUMBER;
        v_error_msg         VARCHAR2(2000);
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные и увеличенные размеры
        v_board_size        PLS_INTEGER;
        v_decoded_board     VARCHAR2(200); 
        v_new_board_decoded VARCHAR2(200);
        v_new_board_encoded games.board_position%TYPE;
        
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
        
        -- [ИЗМЕНЕНИЕ] Получаем размер доски и инициализируем кэш
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

        v_decoded_board := decode_board(v_game.board_position);

        -- Определяем цвет игрока (без изменений)
        IF v_game.ai_difficulty IS NOT NULL THEN
            v_player_color := v_game.current_turn;
        ELSE
            IF v_game.player_white_id = p_player_id THEN
                v_player_color := 'W';
            ELSE
                v_player_color := 'B';
            END IF;
        END IF;

        -- Проверка наличия ходов (v_all_legal_moves)
        v_all_legal_moves := find_all_player_moves(v_decoded_board, v_player_color, v_game.rule_id);

        IF v_all_legal_moves.COUNT = 0 THEN
            UPDATE games
            SET status              = 'V',
                end_time            = SYSDATE,
                -- [ИЗМЕНЕНИЕ] Записываем ЦВЕТ победителя (оппонента)
                winner_player_color = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END
            WHERE game_id = p_game_id;
            
            p_status_message := 'Ходов нет. Вы проиграли!';
            p_update_ratings(p_game_id); -- Обновляем рейтинг
            COMMIT;
            RETURN;
        END IF;
        
        -- Логика валидации p_move_notation
        FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
            DECLARE
                v_legal_move r_move := v_all_legal_moves(i);
                v_notation   VARCHAR2(100); -- Увеличен размер
            BEGIN
                -- [ИЗМЕНЕНИЕ] Передаем v_board_size в idx_to_notation
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

        -- Логика подсказки об обязательном взятии
        IF NOT v_is_move_valid THEN
            
            IF v_all_legal_moves.COUNT > 0 AND v_all_legal_moves(1).is_capture = 'Y' THEN
                DECLARE
                    v_notation_str VARCHAR2(100);
                BEGIN
                    v_error_msg := 'Неверный ход. Взятие обязательно! Доступные варианты: ';
                    FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
                        -- [ИЗМЕНЕНИЕ] Передаем v_board_size
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

            -- Стандартная обработка ошибки
            p_audit_log(
                p_player_id  => p_player_id,
                p_game_id    => p_game_id,
                p_event_msg  => SUBSTR(v_error_msg, 1, 255)
            );
            
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            
            p_status_message := v_error_msg;
            ROLLBACK; -- Отменяем транзакцию (т.к. был SELECT FOR UPDATE)
            RETURN;
        END IF;


        -- Логика применения хода к v_new_board_decoded
        v_new_board_decoded := v_decoded_board;
        DECLARE
            v_moving_piece      CHAR(1) := SUBSTR(v_new_board_decoded, v_chosen_move.path(1).start_idx, 1);
            v_start_pos         PLS_INTEGER := v_chosen_move.path(1).start_idx;
            v_end_pos           PLS_INTEGER := v_chosen_move.path(v_chosen_move.path.LAST).end_idx;
        BEGIN
            v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_start_pos + 1);
            IF v_chosen_move.is_capture = 'Y' THEN
                FOR i IN 1 .. v_chosen_move.path.COUNT LOOP
                    v_new_board_decoded := SUBSTR(v_new_board_decoded, 1, v_chosen_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board_decoded, v_chosen_move.path(i).captured_idx + 1);
                END LOOP;
            END IF;
            
            -- Логика превращения в дамку
            IF v_moving_piece IN (c_white_man, c_black_man) THEN
                DECLARE
                    -- [ИЗМЕНЕНИЕ] Используем кэш g_map_by_idx
                    v_end_row PLS_INTEGER := g_map_by_idx(v_end_pos).row_num;
                    -- [ИЗМЕНЕНИЕ] Используем v_board_size
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

        -- Обновляем игру
        UPDATE games
        SET board_position         = v_new_board_encoded,
            current_turn           = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            -- last_move_at        = SYSTIMESTAMP, -- (В схеме v1.2 этого столбца нет)
            -- moves_since_capture = CASE ... -- (В схеме v1.2 этого столбца нет)
            
            -- [ИЗМЕНЕНИЕ] Обновляем поля ничьей в соответствии со схемой
            draw_offer_status      = NULL, 
            draw_offered_by_color  = NULL, 
            draw_offered_at        = NULL
        WHERE game_id = p_game_id;

        -- [ИЗМЕНЕНИЕ] Убран player_id из INSERT, т.к. его нет в схеме v1.2
        INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
        VALUES (p_game_id, v_move_count, p_move_notation, v_chosen_move.is_capture, v_new_board_encoded);
        
        IF p_player_id IS NULL THEN
            p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
        ELSE
            p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
        END IF;

        -- Проверка на конец игры...
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
                UPDATE games SET status = 'V', end_time = SYSDATE, winner_player_color = v_player_color WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Победа! У противника не осталось фигур.';
                
                -- [ИЗМЕНЕНИЕ] Прямое завершение сессий зрителей
                UPDATE spectators SET left_at = SYSDATE 
                WHERE game_id = p_game_id AND left_at IS NULL;
                
                p_audit_log(p_player_id, p_game_id, p_event_msg => 'WIN_NO_PIECES');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;

            -- Проверка "Противник заблокирован (пат)"
            v_next_player_moves := find_all_player_moves(v_new_board_decoded, v_next_turn_color, v_game.rule_id);
            IF v_next_player_moves.COUNT = 0 THEN
                UPDATE games SET status = 'V', end_time = SYSDATE, winner_player_color = v_player_color WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Победа! Противник заблокирован.';

                -- [ИЗМЕНЕНИЕ] Прямое завершение сессий зрителей
                UPDATE spectators SET left_at = SYSDATE 
                WHERE game_id = p_game_id AND left_at IS NULL;
                
                p_audit_log(p_player_id, p_game_id, p_event_msg => 'WIN_PAT');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
        END IF;

            -- Проверка "Ничья по N ходов без взятия"
            -- (Логика 'moves_since_capture' была в коде, но отсутствует в схеме v1.2, пропускаем эту проверку)
            /*
            IF v_game.draw_moves_limit IS NOT NULL AND v_chosen_move.is_capture = 'N' AND (v_game.moves_since_capture + 1) >= v_game.draw_moves_limit THEN
                UPDATE games SET status = 'D', end_time = SYSDATE WHERE game_id = p_game_id;
                p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия.';
                p_audit_log(NULL, p_game_id, 'DRAW_MOVES_LIMIT');
                p_update_ratings(p_game_id);
                COMMIT;
                RETURN;
            END IF;
            */

            -- Проверка "Ничья по троекратному повторению"
            IF v_game.enable_pos_repetition_draw = 'Y' THEN
                SELECT COUNT(*) INTO v_repetition_count FROM game_moves WHERE game_id = p_game_id AND board_position = v_new_board_encoded;
                IF v_repetition_count >= 2 THEN -- (Позиция была 2 раза, стала 3-й)
                    UPDATE games SET status = 'D', end_time = SYSDATE WHERE game_id = p_game_id;
                    p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.';

                    -- [ИЗМЕНЕНИЕ] Прямое завершение сессий зрителей
                    UPDATE spectators SET left_at = SYSDATE 
                    WHERE game_id = p_game_id AND left_at IS NULL;

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
        v_best_move_str  VARCHAR2(100); -- [ИЗМЕНЕНИЕ] Увеличен размер
        v_chosen_move    r_move;
        v_decoded_board  VARCHAR2(200) := decode_board(p_board_position); -- [ИЗМЕНЕНИЕ] Увеличен размер
        v_search_depth   PLS_INTEGER;
        v_minimax_result r_minimax_result;
        v_alpha          NUMBER;
        v_beta           NUMBER;
        
        -- [ИЗМЕНЕНИЕ] Добавлены переменные для размера доски
        v_board_size     PLS_INTEGER;
    BEGIN
        -- [ИЗМЕНЕНИЕ] Определяем размер доски и инициализируем кэш
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

        -- [ИЗМЕНЕНИЕ] Передаем p_rule_id в minimax
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

        -- Логика случайного хода (p_difficulty = 0)
        IF p_difficulty = 0 AND DBMS_RANDOM.VALUE < 0.25 THEN
             DECLARE
                v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
             BEGIN
                IF v_random_moves.COUNT > 0 THEN
                     v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
                END IF;
             END;
         END IF;

        -- Логика формирования нотации
        IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
             -- [ИЗМЕНЕНИЕ] Передаем v_board_size в idx_to_notation
             v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx, v_board_size);
             FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
                 v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                                  || idx_to_notation(v_chosen_move.path(j).end_idx, v_board_size);
             END LOOP;
        ELSE
            -- Fallback, если minimax ничего не вернул
             DECLARE
                v_fallback_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
             BEGIN
                 IF v_fallback_moves.COUNT > 0 THEN
                      v_chosen_move := v_fallback_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_fallback_moves.COUNT + 1)));
                      -- [ИЗМЕНЕНИЕ] Передаем v_board_size
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
    
    --------------------------------------------------------------------------------

    PROCEDURE create_game(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_ai_difficulty       IN CHAR     DEFAULT NULL,
        p_player_color        IN CHAR     DEFAULT NULL,
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
        p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
        p_enable_pos_rep_draw IN CHAR     DEFAULT 'N',
        -- [ИЗМЕНЕНИЕ] Добавлены параметры из новой спецификации
        p_puzzle_id           IN NUMBER   DEFAULT NULL,
        p_daily               IN CHAR     DEFAULT 'N'
    ) IS
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_creator_color       CHAR(1); -- [ИЗМЕНЕНИЕ]
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
        UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_current_player_id;

        -- Проверка, не занят ли игрок (использует уже исправленную get_active_game)
        v_my_active_game_id := get_active_game(v_current_player_id);
        IF v_my_active_game_id IS NOT NULL THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id;
            p_audit_log(v_current_player_id, v_my_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- [ИЗМЕНЕНИЕ] Улучшенная проверка на конфликт параметров
        IF (p_opponent_username IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
           (p_puzzle_id IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
           (p_puzzle_id IS NOT NULL AND p_opponent_username IS NOT NULL)
        THEN
            v_error_msg := 'Конфликт параметров. Нельзя одновременно создавать Задачу, PVE и PVP.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        -- [ИЗМЕНЕНИЕ] Новая логика для создания сессии Задачи
        IF p_puzzle_id IS NOT NULL THEN
            DECLARE
                v_puzzle puzzles%ROWTYPE;
            BEGIN
                SELECT * INTO v_puzzle FROM puzzles WHERE puzzle_id = p_puzzle_id;
                v_initial_position := v_puzzle.board_position;
                v_encoded_position := encode_board(v_initial_position); -- Кодируем, если не закодирована
                v_status := 'A';
                
                -- Определяем, за кого играет игрок в задаче
                IF v_puzzle.turn_to_move = 'W' THEN
                    v_white_player_id := v_current_player_id;
                    v_black_player_id := NULL;
                    v_creator_color   := 'W'; -- Игрок (создатель сессии) играет за W
                ELSE
                    v_white_player_id := NULL;
                    v_black_player_id := v_current_player_id;
                    v_creator_color   := 'B'; -- Игрок (создатель сессии) играет за B
                END IF;

                INSERT INTO games (
                    rule_id, player_white_id, player_black_id, 
                    creator_player_color, -- [ИЗМЕНЕНИЕ]
                    status, current_turn,
                    board_position, 
                    puzzle_id, is_daily_puzzle, puzzle_status
                )
                VALUES (
                    v_puzzle.rule_id, v_white_player_id, v_black_player_id, 
                    v_creator_color, -- [ИЗМЕНЕНИЕ]
                    v_status, v_puzzle.turn_to_move,
                    v_encoded_position,
                    p_puzzle_id, p_daily, 'p' -- p = pending
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
            
        -- [ИЗМЕНЕНИЕ] Остальная логика (PVE/PVP) уходит в ELSIF
        ELSIF p_puzzle_id IS NULL THEN
        
            -- Определение цвета (сохраняем v_creator_color)
            DECLARE
                v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
            BEGIN
                v_creator_color := v_color_choice; -- [ИЗМЕНЕНИЕ] Сохраняем
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

            -- Логика создания игры PvE
            IF p_ai_difficulty IS NOT NULL THEN
                v_status := 'A';
                IF v_white_player_id IS NULL THEN v_white_player_id := NULL; ELSE v_black_player_id := NULL; END IF;

                INSERT INTO games (
                    -- [ИЗМЕНЕНИЕ] creator_player_id -> creator_player_color
                    creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                    board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                    draw_moves_limit, enable_pos_repetition_draw
                )
                VALUES (
                    v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
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
            
            -- Логика создания PvP
            ELSIF p_opponent_username IS NOT NULL THEN
                IF v_current_username = UPPER(p_opponent_username) THEN 
                    v_error_msg := 'Нельзя вызвать самого себя.';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
                v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

                -- Проверка, не занят ли оппонент (использует исправленную get_active_game)
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
                    -- [ИЗМЕНЕНИЕ] creator_player_id -> creator_player_color
                    creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                    board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                    draw_moves_limit, enable_pos_repetition_draw
                )
                VALUES (
                    v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                    v_encoded_position, NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                    p_draw_moves_limit, p_enable_pos_rep_draw
                )
                RETURNING game_id INTO v_game_id;

                v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';
                p_audit_log(v_current_player_id, v_game_id, 'CREATE_CHALLENGE');
                
            -- Логика создания открытой игры
            ELSE
                v_status := 'O'; -- Open
                INSERT INTO games (
                    -- [ИЗМЕНЕНИЕ] creator_player_id -> creator_player_color
                    creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                    board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                    draw_moves_limit, enable_pos_repetition_draw
                )
                VALUES (
                    v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                    v_encoded_position, NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                    p_draw_moves_limit, p_enable_pos_rep_draw
                )
                RETURNING game_id INTO v_game_id;

                v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
                p_audit_log(v_current_player_id, v_game_id, 'CREATE_OPEN_GAME');
            END IF;
            
        END IF; -- Конец IF p_puzzle_id IS NOT NULL

        COMMIT;
        DBMS_OUTPUT.PUT_LINE(v_status_message);
        
        -- Вывод доски (если ИИ сделал первый ход или если это задача)
        IF (p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL) OR (p_puzzle_id IS NOT NULL) THEN
             BEGIN
                -- [ИЗМЕНЕНИЕ] print_board -> print_active_board
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

    --------------------------------------------------------------------------------

    PROCEDURE join_game(p_game_id IN NUMBER) IS
        v_game           games%ROWTYPE;
        v_player_id      players.player_id%TYPE;
        v_active_game_id NUMBER;
        v_error_msg      VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;

        v_active_game_id := get_active_game(v_player_id);

        IF v_active_game_id IS NOT NULL THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

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
            -- [ИЗМЕНЕНИЕ] Логика определения создателя
            DECLARE
                v_creator_id players.player_id%TYPE;
            BEGIN
                IF v_game.creator_player_color = 'W' THEN
                    v_creator_id := v_game.player_white_id;
                ELSE
                    v_creator_id := v_game.player_black_id;
                END IF;
                
                -- Проверяем, что игрок есть в списке И не является создателем
                IF NOT (v_player_id IN (v_game.player_white_id, v_game.player_black_id) AND v_player_id != v_creator_id) THEN
                    v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                    p_audit_log(v_player_id, p_game_id, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    ROLLBACK; 
                    RETURN;
                END IF;
            END;
            
        ELSIF v_game.status = 'O' THEN -- Присоединение к открытой игре
            -- [ИЗМЕНЕНИЕ] Проверяем, не пытается ли игрок присоединиться к своей же игре
            IF v_player_id = v_game.player_white_id OR v_player_id = v_game.player_black_id THEN
                v_error_msg := 'Нельзя присоединиться к собственной открытой игре (ID: ' || p_game_id || ').';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
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
        
        -- Если игра 'O', вписываем ID игрока в пустой слот
        IF v_game.status = 'O' THEN
            UPDATE games
            SET player_white_id = NVL(v_game.player_white_id, v_player_id),
                player_black_id = NVL(v_game.player_black_id, v_player_id),
                status          = 'A',
                start_time      = SYSDATE
                -- [ИЗМЕНЕНИЕ] Убран last_move_at
            WHERE game_id = p_game_id;
        ELSE -- 'C'
            UPDATE games
            SET status     = 'A',
                start_time = SYSDATE
                -- [ИЗМЕНЕНИЕ] Убран last_move_at
            WHERE game_id = p_game_id;
        END IF;
        
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
    
    --------------------------------------------------------------------------------

    PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N') IS
        v_game        games%ROWTYPE;
        v_player_id   players.player_id%TYPE;
        v_game_id     NUMBER;
        v_error_msg   VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        
        -- 1. Проверка на режим зрителя
        DECLARE
            v_spectating_game_id NUMBER;
        BEGIN
            v_spectating_game_id := get_active_spectator_session(v_player_id);
            IF v_spectating_game_id IS NOT NULL THEN
                v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя сдаться.';
                p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_watching; чтобы выйти из режима просмотра ]--');
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

        -- Логика выхода из Задачи
        IF v_game.puzzle_id IS NOT NULL THEN
            UPDATE games
            SET status = 'V', -- Void (Отменена)
                end_time = SYSDATE,
                puzzle_status = 'f' -- Failed
            WHERE game_id = v_game_id;
            
            UPDATE spectators SET left_at = SYSDATE 
            WHERE game_id = v_game_id AND left_at IS NULL;
            
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'QUIT_PUZZLE');
            DBMS_OUTPUT.PUT_LINE('[OK] Вы вышли из попытки решения задачи (ID сессии: ' || v_game_id || ').');
            
        -- Логика PVE/PVP
        ELSE
            DECLARE
                v_winner_id       players.player_id%TYPE;
                v_winner_color    CHAR(1);
                v_winner_username players.username%TYPE;
            BEGIN
                -- Определяем победителя (ID и Цвет)
                IF v_player_id = v_game.player_white_id THEN
                    v_winner_id := v_game.player_black_id;
                    v_winner_color := 'B';
                ELSE
                    v_winner_id := v_game.player_white_id;
                    v_winner_color := 'W';
                END IF;

                -- 1. Завершаем ИГРУ
                UPDATE games
                SET status              = 'R', -- Resigned
                    winner_player_color = v_winner_color,
                    end_time            = SYSDATE
                WHERE game_id = v_game_id;

                -- 2. Кикаем зрителей
                UPDATE spectators SET left_at = SYSDATE 
                WHERE game_id = v_game_id AND left_at IS NULL;

                -- 3. [НОВАЯ ЛОГИКА] Завершаем МАТЧ, если флаг установлен
                IF UPPER(p_resign_match) = 'Y' AND v_game.match_id IS NOT NULL THEN
                    UPDATE matches
                    SET status = 'C', -- Completed
                        winner_player_id = v_winner_id -- (ID оппонента)
                    WHERE match_id = v_game.match_id;
                    
                    p_audit_log(v_player_id, v_game.game_id, p_event_msg => 'MATCH_RESIGN');
                    DBMS_OUTPUT.PUT_LINE('Вы также сдались во всем матче (ID: ' || v_game.match_id || ').');
                END IF;

                -- 4. Обновляем рейтинг и выводим сообщение
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

    --------------------------------------------------------------------------------
   
    FUNCTION f_get_board_as_clob(
        p_board_position  IN VARCHAR2,
        p_highlight_indices IN t_map_indices DEFAULT t_map_indices()
    ) RETURN CLOB IS
        v_clob          CLOB;
        v_char          CHAR(1);
        v_linear_idx    PLS_INTEGER;
        v_decoded_board VARCHAR2(200) := decode_board(p_board_position); -- [ИЗМЕНЕНИЕ]
        c_nl CONSTANT   VARCHAR2(1)   := CHR(10);
        
        -- [ИЗМЕНЕНИЕ] Динамические переменные
        v_board_size    PLS_INTEGER;
        v_total_squares PLS_INTEGER;
        v_header        VARCHAR2(200) := '  |';
        v_separator     VARCHAR2(200) := '--+';
        
    BEGIN
        DBMS_LOB.createtemporary(v_clob, TRUE);

        -- [ИЗМЕНЕНИЕ] Динамическое определение размера
        v_total_squares := LENGTH(v_decoded_board);
        v_board_size    := SQRT(v_total_squares);
        
        -- Если доска не квадратная (ошибка), возвращаем пустой CLOB
        IF v_board_size != TRUNC(v_board_size) THEN 
            DBMS_LOB.append(v_clob, 'ОШИБКА: Длина доски (' || v_total_squares || ') не является полным квадратом.');
            RETURN v_clob;
        END IF;
        
        -- Инициализируем кэш (на всякий случай, если он не был загружен)
        p_init_board_map(v_board_size);
        
        -- [ИЗМЕНЕНИЕ] Динамическое создание хедера и разделителя
        FOR c IN 1 .. v_board_size LOOP
            v_header    := v_header    || ' ' || CHR(ASCII('A') + c - 1) || ' ';
            v_separator := v_separator || '---';
        END LOOP;
        v_header    := v_header    || ' |';
        v_separator := v_separator || '+--';

        DBMS_LOB.append(v_clob, v_header || c_nl);
        DBMS_LOB.append(v_clob, v_separator || c_nl);

        -- [ИЗМЕНЕНИЕ] Динамические циклы
        FOR r IN REVERSE 1 .. v_board_size LOOP
            DBMS_LOB.append(v_clob, LPAD(r, 2, ' ') || '|'); -- LPAD для '10'
            FOR c IN 1 .. v_board_size LOOP
                -- [ИЗМЕНЕНИЕ] Динамический индекс
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
                    DBMS_LOB.append(v_clob, '   '); -- 3 пробела
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
            DBMS_LOB.freetemporary(v_clob);
            DBMS_LOB.createtemporary(v_clob, TRUE);
            DBMS_LOB.append(v_clob, 'КРИТИЧЕСКАЯ ОШИБКА в f_get_board_as_clob: ' || SQLERRM);
            RETURN v_clob;
    END f_get_board_as_clob;

    --------------------------------------------------------------------------------

PROCEDURE watch_game_replay(
        p_game_id       IN NUMBER,
        p_username      IN VARCHAR2 DEFAULT NULL, -- (Параметр не используется в этой логике)
        p_moves_to_show IN NUMBER DEFAULT 1
    ) IS
        v_player_id     players.player_id%TYPE;
        v_seq_name      VARCHAR2(64);
        v_job_name      VARCHAR2(64);
        v_move_num      NUMBER;
        v_color_str     VARCHAR2(30);
        v_session_exists PLS_INTEGER;

        v_game_rec      games%ROWTYPE;
        v_max_moves     NUMBER;
        v_winner_name   players.username%TYPE;
        v_loser_name    players.username%TYPE;
        v_final_message VARCHAR2(250);
        v_error_msg     VARCHAR2(255);
        
        v_replay_finished BOOLEAN := FALSE;
        v_replay_error    BOOLEAN := FALSE;
        
        -- Используем v_game_protocol (который мы исправили в предыдущем шаге)
        CURSOR c_game_moves (cp_game_id NUMBER, cp_move_number NUMBER) IS
            SELECT
                username,       -- Имя из VIEW
                player_color,   -- Цвет из VIEW
                move_notation,
                board_position
            FROM v_game_protocol
            WHERE game_id = cp_game_id AND move_number = cp_move_number;

    BEGIN
        v_player_id := get_or_create_player_id(USER);
        UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
        
        v_seq_name  := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id;
        v_job_name  := 'DROP_REPLAY_SEQ_' || p_game_id || '_' || v_player_id;

        -- === 1. ПРОВЕРКА/СОЗДАНИЕ СЕССИИ ===
        
        -- Проверяем, существует ли уже Sequence
        SELECT COUNT(*) INTO v_session_exists 
        FROM user_sequences 
        WHERE sequence_name = v_seq_name;

        IF v_session_exists = 0 THEN
            -- Сессии нет. Создаем ее (логика из start_replay_session)
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
            
            -- Чистим старый JOB, если он вдруг остался
            BEGIN DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;

            EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seq_name || 
                              ' START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE ' || 
                              v_max_moves || ' NOCYCLE NOCACHE';
            
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
            
        END IF; -- Конец создания сессии
        
        -- === 2. ВЫВОД ХОДОВ ===
        
        -- (Нам все еще нужна v_game_rec для финального сообщения)
        IF v_game_rec.game_id IS NULL THEN
             SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
        END IF;

        FOR i IN 1 .. p_moves_to_show LOOP
            BEGIN
                -- 2.1. Пытаемся получить следующий ход
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF SQLCODE = -8004 THEN -- Sequence MAXVALUE exceeded
                            v_replay_finished := TRUE;
                        ELSE -- -2289 (Sequence удален?) или другая ошибка
                            v_replay_error := TRUE;
                            v_error_msg := 'Ошибка сессии просмотра (ID: ' || p_game_id || '). ' || SQLERRM;
                            p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 255));
                            DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        END IF;
                END;

                -- 2.2. Обрабатываем флаги
                IF v_replay_error THEN
                    EXIT; -- Выходим из цикла FOR
                END IF;

                IF v_replay_finished THEN
                    BEGIN
                        -- Логика финала (исправлена под схему v1.2)
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
                    EXIT; -- Выходим из цикла FOR
                END IF;

                -- 2.3. Печатаем ход
                FOR move_rec IN c_game_moves(p_game_id, v_move_num) LOOP
                    -- [ИЗМЕНЕНИЕ] Форматирование вывода по вашему запросу
                    v_color_str := CASE move_rec.player_color WHEN 'W' THEN '(Белые)' ELSE '(Черные)' END;
                    DBMS_OUTPUT.PUT_LINE('---');
                    DBMS_OUTPUT.PUT_LINE(
                        'Ход ' || v_move_num || ' ' || 
                        RPAD(NVL(move_rec.username, 'AI'), 20) || ' ' || -- NVL на случай, если ИИ был в игре
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
    
    ---------------------------------------------------------------------------------

    PROCEDURE stop_spectating IS
        v_player_id players.player_id%TYPE;
        v_count     PLS_INTEGER;
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        -- [ИЗМЕНЕНИЕ] Встроенная логика
        UPDATE spectators
        SET left_at = SYSDATE
        WHERE player_id = v_player_id
          AND left_at IS NULL
        RETURNING COUNT(*) INTO v_count; -- (Возвращает 1, если что-то было обновлено)
        
        COMMIT;
        
        IF v_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('Вы вышли из режима просмотра.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Вы не находились в режиме просмотра.');
        END IF;
        
    END stop_spectating;

    --------------------------------------------------------------------------------

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

    BEGIN
        v_viewer_player_id := get_or_create_player_id(USER);
        
        -- === 1. ЛОГИКА ПОИСКА ИГРЫ ===
        -- ... (Логика поиска v_target_game_id остается без изменений) ...
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
        
        -- === 2. ПРОВЕРКА ИГРЫ И ЛОГИКА ЗРИТЕЛЯ ===
        
        -- [ИЗМЕНЕНИЕ] 1. Завершаем ЛЮБУЮ другую сессию просмотра.
        UPDATE spectators
        SET left_at = SYSDATE
        WHERE player_id = v_viewer_player_id
          AND left_at IS NULL
          AND game_id != v_target_game_id; -- (Не трогаем текущую, если мы ее уже смотрим)

        BEGIN
            SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
                p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
        -- [ИЗМЕНЕНИЕ] 2. Входим в режим Зрителя
        IF v_viewer_player_id NOT IN (v_game.player_white_id, v_game.player_black_id)
           AND v_game.status IN ('A', 'O', 'C')
        THEN
            -- Используем MERGE, чтобы не создавать дубликат, если мы уже смотрим
            MERGE INTO spectators s
            USING (SELECT v_viewer_player_id AS player_id, v_target_game_id AS game_id FROM DUAL) d
            ON (s.player_id = d.player_id AND s.game_id = d.game_id AND s.left_at IS NULL)
            WHEN NOT MATCHED THEN
                INSERT (player_id, game_id, joined_at)
                VALUES (d.player_id, d.game_id, SYSDATE);
            
            p_audit_log(v_viewer_player_id, v_target_game_id, 'SPECTATOR_JOIN');
            DBMS_OUTPUT.PUT_LINE('--[ Вы вошли в режим просмотра (ID: ' || v_target_game_id || ') ]--');
        END IF;
        
        COMMIT; -- Фиксируем изменения в spectators

        -- === 3. ЛОГИКА ОЖИДАНИЯ (p_wait_for_turn) ===
        DECLARE
            v_active_player_id  players.player_id%TYPE;
            v_highlight_indices t_map_indices;
            v_legal_moves       t_move_list;
            v_decoded_board     VARCHAR2(200);
        BEGIN
            -- ... (Логика цикла ожидания остается без изменений) ...
            IF v_game.player_white_id = v_viewer_player_id THEN
                v_my_color := 'W';
            ELSIF v_game.player_black_id = v_viewer_player_id THEN
                v_my_color := 'B';
            ELSE
                v_my_color := NULL; 
            END IF;

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
            
            -- === 4. ЛОГИКА ОТРИСОВКИ ===
            
            IF v_game.status NOT IN ('A', 'O', 'C') THEN
                v_error_msg := 'Игра с id = ' || v_target_game_id || ' закончена. (Статус: ' || v_game.status || ')';
                p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                DBMS_OUTPUT.PUT_LINE('-- Используйте watch_game_replay(' || v_target_game_id || ') для просмотра.');
                
                -- [ИЗМЕНЕНИЕ] Если игра закончилась, пока мы ждали, выходим из просмотра
                UPDATE spectators SET left_at = SYSDATE 
                WHERE player_id = v_viewer_player_id AND game_id = v_target_game_id AND left_at IS NULL;
                COMMIT;
                
                RETURN;
            END IF;

            v_decoded_board := decode_board(v_game.board_position);
            v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
            
            -- 4.1. Логика подсветки
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
                WHEN OTHERS THEN NULL; 
            END;
            
            -- 4.2. Логика печати
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

    --------------------------------------------------------------------------------

    PROCEDURE make_move(p_move_notation IN VARCHAR2) IS
        v_game_id   NUMBER;
        v_game      games%ROWTYPE;
        v_player_id players.player_id%TYPE;
        v_human_msg VARCHAR2(2000); -- [ИЗМЕНЕНИЕ] Увеличен размер
        v_ai_msg    VARCHAR2(2000); -- [ИЗМЕНЕНИЕ] Увеличен размер
        c_nl CONSTANT VARCHAR2(1) := CHR(10);
        v_error_msg VARCHAR2(255);  -- [ИЗМЕНЕНИЕ] Увеличен размер
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        v_game_id   := get_active_game(v_player_id);
        
        -- [ИЗМЕНЕНИЕ] SYSTIMESTAMP -> SYSDATE для типа DATE
        UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id; 
        
        IF v_game_id IS NULL THEN
            v_error_msg := 'Нет активных игр, чтобы сделать ход.';
            -- [ИЗМЕНЕНИЕ] p_event_type -> p_event_msg
            p_audit_log(
                p_player_id => v_player_id, 
                p_game_id   => NULL, 
                p_event_msg => v_error_msg 
            );
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        SELECT * INTO v_game FROM games WHERE game_id = v_game_id;

        IF v_game.status <> 'A' THEN
            v_error_msg := 'Игра (ID: ' || v_game_id || ') еще не активна. Противник не подключился.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg); -- [ИЗМЕНЕНИЕ]
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        IF (v_game.current_turn = 'W' AND v_game.player_white_id != v_player_id) OR 
           (v_game.current_turn = 'B' AND v_game.player_black_id != v_player_id) 
        THEN
            v_error_msg := 'Сейчас не ваш ход. (ID Игры: ' || v_game_id || ', Очередь: ' || v_game.current_turn || ').';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg); -- [ИЗМЕНЕНИЕ]
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- Ход человека
        p_process_move(v_game_id, p_move_notation, v_player_id, v_human_msg);
        
        -- [ИЗМЕНЕНИЕ] Улучшенная проверка на ошибку
        IF INSTR(LOWER(v_human_msg), 'неверный ход') > 0 OR INSTR(LOWER(v_human_msg), 'нелегальный ход') > 0 THEN
            RETURN; -- Сообщение об ошибке уже было выведено в p_process_move
        END IF;
        
        -- [ИЗМЕНЕНИЕ] Вывод доски после хода человека
        BEGIN
            print_active_board(p_game_id => v_game_id); 
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        
        -- Ход ИИ (если применимо)
        DECLARE
            v_next_game_state games%ROWTYPE;
            v_ai_move         VARCHAR2(100); -- Увеличен размер
        BEGIN
            -- [ИЗМЕНЕНИЕ] Перечитываем состояние, так как p_process_move сделал COMMIT
            SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;

            -- Проверка, что сейчас ход ИИ
            IF v_next_game_state.status = 'A' AND v_next_game_state.ai_difficulty IS NOT NULL AND
               ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id IS NULL) OR
                (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id IS NULL))
            THEN
                v_ai_move := get_ai_move(
                    p_board_position => v_next_game_state.board_position, 
                    p_ai_color       => v_next_game_state.current_turn, 
                    p_rule_id        => v_next_game_state.rule_id, 
                    p_difficulty     => v_next_game_state.ai_difficulty
                );

                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg); -- ID ИИ = NULL
                    DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                    
                    -- [ИЗМЕНЕНИЕ] Вывод доски после хода ИИ
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

    PROCEDURE draw(p_action IN CHAR) IS
        v_player_id players.player_id%TYPE;
        v_game_id   games.game_id%TYPE;
        v_game      games%ROWTYPE;
        v_error_msg VARCHAR2(255);
        v_my_color  CHAR(1);
        v_action    CHAR(1) := UPPER(p_action); -- [ИЗМЕНЕНИЕ]
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        -- 1. [ПРОВЕРКА] Не находится ли игрок в режиме просмотра
        DECLARE
            v_spectating_game_id NUMBER;
        BEGIN
            v_spectating_game_id := get_active_spectator_session(v_player_id);
            IF v_spectating_game_id IS NOT NULL THEN
                v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя управлять ничьей.';
                p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_watching; чтобы выйти из режима просмотра ]--');
                RETURN;
            END IF;
        END;

        -- 2. [ПРОВЕРКА] Найти активную игру
        v_game_id := get_active_game(v_player_id);
        IF v_game_id IS NULL THEN
            v_error_msg := 'У вас нет активной игры.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        -- 3. [ПРОВЕРКА] Блокируем, загружаем и проверяем игру
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
            ROLLBACK; -- Снять FOR UPDATE
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

        -- === 4. ГЛАВНАЯ ЛОГИКА ===
        
        -- O = Offer (Предложить)
        IF v_action = 'O' THEN -- [ИЗМЕНЕНИЕ]
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

        -- A = Accept (Принять)
        ELSIF v_action = 'A' THEN -- [ИЗМЕНЕНИЕ]
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

            UPDATE games
            SET status = 'D', -- Draw
                end_time = SYSDATE,
                draw_offer_status = 'S' -- (S)uccess
            WHERE game_id = v_game_id;
            
            -- Кикаем зрителей
            UPDATE spectators SET left_at = SYSDATE 
            WHERE game_id = v_game_id AND left_at IS NULL;

            p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_ACCEPT');
            p_update_ratings(v_game_id); 
            DBMS_OUTPUT.PUT_LINE('Ничья по соглашению сторон.');

        -- C = Cancel (Отменить) / Decline (Отклонить)
        ELSIF v_action = 'C' THEN -- [ИЗМЕНЕНИЕ]
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

        -- 5. Фиксируем изменения
        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END draw;

    --------------------------------------------------------------------------------

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
        v_opponent_player_id players.player_id%TYPE;
        v_error_msg          VARCHAR2(255);
        v_status_message     VARCHAR2(255);
        
        v_game_id            games.game_id%TYPE;
        v_match_id           matches.match_id%TYPE;
        
    BEGIN
        v_current_player_id := get_or_create_player_id(USER);
        
        -- 1. Проверки (зритель, занятость)
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
        
        -- 2. Создаем ПЕРВУЮ ИГРУ матча
        -- Мы передаем все параметры матча в create_game
        -- create_game сама обработает занятость оппонента и создаст игру (статус 'C' или 'O')
        create_game(
            p_opponent_username   => p_opponent_username, -- (Может быть NULL для "Открытого" матча)
            p_ai_difficulty       => NULL, -- (Матчи не могут быть с ИИ)
            p_player_color        => p_player_color,
            p_rule_id             => p_rule_id,
            p_time_limit_move_sec => p_time_limit_move_sec,
            p_time_limit_game_sec => p_time_limit_game_sec,
            p_draw_moves_limit    => p_draw_moves_limit,
            p_enable_pos_rep_draw => p_enable_pos_rep_draw,
            p_puzzle_id           => NULL,
            p_daily               => 'N'
        );
        
        -- 3. Находим ID только что созданной игры
        v_game_id := get_active_game(v_current_player_id);
        
        -- 4. Если create_game не удался (например, оппонент занят), v_game_id будет NULL
        IF v_game_id IS NULL THEN
            -- Сообщение об ошибке уже было выведено из create_game
            RETURN;
        END IF;

        -- 5. Создаем запись о Матче
        INSERT INTO matches (
            rule_id, 
            games_to_win, 
            status -- (C=Challenged, O=Open)
        )
        SELECT 
            g.rule_id,
            p_games_to_win,
            g.status -- (Берем статус 'C' или 'O' из созданной игры)
        FROM games g
        WHERE g.game_id = v_game_id
        RETURNING match_id INTO v_match_id;

        -- 6. Связываем Игру и Матч
        UPDATE games
        SET match_id = v_match_id
        WHERE game_id = v_game_id;
        
        -- 7. Формируем сообщение
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

    PROCEDURE join_match(p_match_id IN NUMBER) IS
        v_player_id players.player_id%TYPE;
        v_match     matches%ROWTYPE;
        v_game      games%ROWTYPE;
        v_error_msg VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        -- 1. Проверки (зритель, занятость)
        IF get_active_game(v_player_id) IS NOT NULL THEN
            v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- 2. Находим и блокируем Матч
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

        -- 3. Находим связанную Игру (которая ожидает)
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
        
        -- 4. Проверяем статус Матча (должен совпадать с игрой)
        IF v_match.status NOT IN ('O', 'C') THEN
            v_error_msg := 'Матч (ID: ' || p_match_id || ') уже начат или завершен (Статус: ' || v_match.status || ').';
            p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        -- 5. Вызываем join_game. 
        -- (join_game сам проверит, что мы являемся оппонентом (для 'C') 
        -- или не являемся создателем (для 'O'))
        
        join_game(v_game.game_id);
        
        -- 6. Проверяем, удалось ли присоединиться
        DECLARE
            v_game_status CHAR(1);
        BEGIN
            SELECT status INTO v_game_status 
            FROM games 
            WHERE game_id = v_game.game_id;
            
            -- Если статус игры 'A', значит join_game прошел успешно
            IF v_game_status = 'A' THEN
                -- Активируем Матч
                UPDATE matches
                SET status = 'A'
                WHERE match_id = p_match_id;
                
                DBMS_OUTPUT.PUT_LINE('Вы присоединились к матчу (ID: ' || p_match_id || '). Начинается первая игра (ID: ' || v_game.game_id || ').');
                p_audit_log(v_player_id, v_game.game_id, 'MATCH_JOINED');
                COMMIT;
            ELSE
                -- join_game вывел ошибку, мы просто откатываем FOR UPDATE
                ROLLBACK;
            END IF;
        END;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END join_match;

    PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N') IS
        v_game        games%ROWTYPE;
        v_player_id   players.player_id%TYPE;
        v_game_id     NUMBER;
        v_error_msg   VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        
        -- 1. Проверка на режим зрителя
        DECLARE
            v_spectating_game_id NUMBER;
        BEGIN
            v_spectating_game_id := get_active_spectator_session(v_player_id);
            IF v_spectating_game_id IS NOT NULL THEN
                v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя сдаться.';
                p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_watching; чтобы выйти из режима просмотра ]--');
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

        -- Логика выхода из Задачи
        IF v_game.puzzle_id IS NOT NULL THEN
            UPDATE games
            SET status = 'V', -- Void (Отменена)
                end_time = SYSDATE,
                puzzle_status = 'f' -- Failed
            WHERE game_id = v_game_id;
            
            -- Кикаем зрителей
            UPDATE spectators SET left_at = SYSDATE 
            WHERE game_id = v_game_id AND left_at IS NULL;
            
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'QUIT_PUZZLE');
            DBMS_OUTPUT.PUT_LINE('[OK] Вы вышли из попытки решения задачи (ID сессии: ' || v_game_id || ').');
            
        -- Логика PVE/PVP
        ELSE
            DECLARE
                v_winner_id       players.player_id%TYPE;
                v_winner_color    CHAR(1);
                v_winner_username players.username%TYPE;
            BEGIN
                -- Определяем победителя (ID и Цвет)
                IF v_player_id = v_game.player_white_id THEN
                    v_winner_id := v_game.player_black_id;
                    v_winner_color := 'B';
                ELSE
                    v_winner_id := v_game.player_white_id;
                    v_winner_color := 'W';
                END IF;

                -- 1. Завершаем ИГРУ
                UPDATE games
                SET status              = 'R', -- Resigned
                    winner_player_color = v_winner_color,
                    end_time            = SYSDATE
                WHERE game_id = v_game_id;

                -- 2. Кикаем зрителей
                UPDATE spectators SET left_at = SYSDATE 
                WHERE game_id = v_game_id AND left_at IS NULL;

                -- 3. [НОВАЯ ЛОГИКА] Завершаем МАТЧ, если флаг установлен
                IF UPPER(p_resign_match) = 'Y' AND v_game.match_id IS NOT NULL THEN
                    UPDATE matches
                    SET status = 'C', -- Completed
                        winner_player_id = v_winner_id -- (ID оппонента)
                    WHERE match_id = v_game.match_id;
                    
                    p_audit_log(v_player_id, v_game.game_id, p_event_msg => 'MATCH_RESIGN');
                    DBMS_OUTPUT.PUT_LINE('Вы также сдались во всем матче (ID: ' || v_game.match_id || ').');
                END IF;

                -- 4. Обновляем рейтинг и выводим сообщение
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

    PROCEDURE cancel_game IS
        v_game_id   NUMBER;
        v_player_id players.player_id%TYPE;
        v_game      games%ROWTYPE;
        v_error_msg VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(user);
        
        -- 1. Проверка на режим зрителя
        DECLARE
            v_spectating_game_id NUMBER;
        BEGIN
            v_spectating_game_id := get_active_spectator_session(v_player_id);
            IF v_spectating_game_id IS NOT NULL THEN
                v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя отменить игру.';
                p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_watching; чтобы выйти из режима просмотра ]--');
                RETURN;
            END IF;
        END;
        
        UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
        
        -- 2. Находим активную сессию (игру)
        v_game_id := get_active_game(v_player_id);
        IF v_game_id IS NULL THEN
            v_error_msg := 'Нет активных игр или вызовов для отмены.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg); 
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        -- 3. Блокируем и проверяем игру
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

        IF v_game.status NOT IN ('O', 'C') THEN
            v_error_msg := 'Эту игру (ID: ' || v_game_id || ') нельзя отменить (статус '||v_game.status||'). Используйте resign_game, чтобы сдаться.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        -- 4. [НОВАЯ ЛОГИКА] Проверяем, связан ли матч
        IF v_game.match_id IS NOT NULL THEN
            -- Удаляем МАТЧ
            DELETE FROM matches 
            WHERE match_id = v_game.match_id;
            
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'MATCH_CANCEL');
            DBMS_OUTPUT.PUT_LINE('Связанный вызов на матч (ID: ' || v_game.match_id || ') также отменен.');
        END IF;

        -- 5. Удаляем ИГРУ (и зрителей через ON DELETE CASCADE)
        DELETE FROM games WHERE game_id = v_game_id;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'CANCEL_GAME');
        DBMS_OUTPUT.PUT_LINE('Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_audit_log(v_player_id, v_game_id, p_event_msg => SUBSTR('Ошибка cancel_game: ' || SQLERRM, 1, 255));
            RAISE;
    END cancel_game;


    --------------------------------------------------------------------------------
    -- ЗАГЛУШКИ ДЛЯ ЗАДАЧ (PUZZLES)
    --------------------------------------------------------------------------------   
    PROCEDURE create_puzzle(
        p_board_position   IN CLOB, -- [ИЗМЕНЕНИЕ] VARCHAR2 заменен на CLOB для многострочного ввода
        p_turn_to_move     IN CHAR,
        p_moves_to_solve   IN NUMBER DEFAULT NULL,
        p_difficulty_level IN CHAR DEFAULT '1' -- [ИЗМЕНЕНИЕ] Тип изменен на CHAR (как в PKS)
    ) IS
        v_player_id players.player_id%TYPE;
        v_error_msg VARCHAR2(500);
        
        -- Переменные для валидации
        v_single_line_board VARCHAR2(200) := '';
        v_line              VARCHAR2(200);
        v_offset            NUMBER := 1;
        v_clob_len          NUMBER;
        v_line_break        NUMBER;
        c_nl                CHAR(1) := CHR(10);
        v_board_size        NUMBER;
        v_rule_id           game_rules.rule_id%TYPE;
        v_encoded_board     puzzles.board_position%TYPE;
        v_new_puzzle_id     puzzles.puzzle_id%TYPE;

    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        -- 1. Проверка сессии (нельзя создавать, если играешь или смотришь)
        IF get_active_game(v_player_id) IS NOT NULL THEN
            v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы создать задачу.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        -- 2. Базовая валидация параметров
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

        -- 3. Валидация и парсинг доски (CLOB)
        BEGIN
            v_clob_len := DBMS_LOB.getlength(p_board_position);
            
            -- 3.1. Парсим CLOB в одну строку (v_single_line_board)
            WHILE v_offset <= v_clob_len LOOP
                v_line_break := DBMS_LOB.instr(p_board_position, c_nl, v_offset);
                
                IF v_line_break = 0 THEN -- Последняя строка
                    v_line := DBMS_LOB.substr(p_board_position, v_clob_len - v_offset + 1, v_offset);
                    v_offset := v_clob_len + 1;
                ELSE
                    v_line := DBMS_LOB.substr(p_board_position, v_line_break - v_offset, v_offset);
                    v_offset := v_line_break + 1;
                END IF;
                
                -- Очищаем пробелы, табуляции и переносы строк
                v_line := REGEXP_REPLACE(v_line, '[[:space:]]', '');
                
                IF LENGTH(v_line) > 0 THEN
                    v_single_line_board := v_single_line_board || v_line;
                END IF;
            END LOOP;

            -- 3.2. Проверяем длину (64 или 100)
            IF LENGTH(v_single_line_board) = 64 THEN
                v_board_size := 8;
            ELSIF LENGTH(v_single_line_board) = 100 THEN
                v_board_size := 10;
            ELSE
                v_error_msg := 'Ошибка: Неверный размер доски. Ожидалось 64 (8x8) или 100 (10x10) символов, получено: ' || LENGTH(v_single_line_board);
                RAISE_APPLICATION_ERROR(-20001, v_error_msg);
            END IF;
            
            -- 3.3. Проверяем символы
            IF REGEXP_LIKE(v_single_line_board, '[^wWbB+]') THEN
                v_error_msg := 'Ошибка: Доска содержит недопустимые символы. Разрешены только: w, W, b, B, +.';
                RAISE_APPLICATION_ERROR(-20002, v_error_msg);
            END IF;
            
            -- 3.4. Проверяем наличие фигур
            IF INSTR(v_single_line_board, 'w') = 0 AND INSTR(v_single_line_board, 'W') = 0 THEN
                v_error_msg := 'Ошибка: На доске нет ни одной белой фигуры (w, W).';
                RAISE_APPLICATION_ERROR(-20003, v_error_msg);
            END IF;
            IF INSTR(v_single_line_board, 'b') = 0 AND INSTR(v_single_line_board, 'B') = 0 THEN
                v_error_msg := 'Ошибка: На доске нет ни одной черной фигуры (b, B).';
                RAISE_APPLICATION_ERROR(-20004, v_error_msg);
            END IF;

            -- 4. Получаем rule_id по размеру
            BEGIN
                SELECT rule_id INTO v_rule_id
                FROM game_rules
                WHERE board_size = v_board_size
                AND ROWNUM = 1; -- Берем первое правило, подходящее по размеру
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_error_msg := 'Ошибка: Не найдено правило в game_rules для доски ' || v_board_size || 'x' || v_board_size;
                    RAISE_APPLICATION_ERROR(-20005, v_error_msg);
            END;

            -- 5. Кодируем и вставляем
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
                -- v_error_msg будет заполнен из RAISE_APPLICATION_ERROR
                IF v_error_msg IS NULL THEN
                   v_error_msg := 'Неизвестная ошибка: ' || SQLERRM;
                END IF;
                p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 255));
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
        END; -- Конец блока валидации

    END create_puzzle;
    
    PROCEDURE show_puzzles(
        p_difficulty IN NUMBER DEFAULT NULL, 
        p_puzzle_id  IN NUMBER DEFAULT NULL
    ) IS
        v_player_id players.player_id%TYPE;
        v_found     BOOLEAN := FALSE;
        v_header    VARCHAR2(200);
        
        -- Курсор для выборки задач
        CURSOR c_puzzles IS
            SELECT 
                puz.puzzle_id,
                puz.difficulty_level,
                puz.moves_to_solve,
                NVL(pl.username, 'System') AS creator_username,
                puz.board_position,
                puz.turn_to_move
            FROM puzzles puz
            LEFT JOIN players pl ON puz.created_by_player_id = pl.player_id
            WHERE 
                -- 1. Либо мы ищем по конкретному ID
                (p_puzzle_id IS NOT NULL AND puz.puzzle_id = p_puzzle_id)
                OR 
                -- 2. Либо мы ищем по сложности (или все)
                (p_puzzle_id IS NULL AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty));
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        -- Проверка сессии (get_active_game) не нужна, т.к. это просто просмотр

        DBMS_OUTPUT.PUT_LINE('--- Список Задач ---');
        
        -- Динамический заголовок
        IF p_puzzle_id IS NOT NULL THEN
            v_header := ' (Поиск по ID: ' || p_puzzle_id || ')';
        ELSIF p_difficulty IS NOT NULL THEN
            v_header := ' (Фильтр по Сложности: ' || p_difficulty || ')';
        ELSE
            v_header := ' (Все задачи)';
        END IF;
        DBMS_OUTPUT.PUT_LINE(v_header);
        
        DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || RPAD('Сложность', 10) || RPAD('Ходов', 6) || RPAD('Автор', 15) || RPAD('Ход', 4) || 'Позиция (RLE)');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 5, '-') || ' ' || RPAD('-', 10, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 15, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

        FOR r IN c_puzzles LOOP
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.puzzle_id, 5) || 
                RPAD(r.difficulty_level, 10) || 
                RPAD(NVL(TO_CHAR(r.moves_to_solve), 'N/A'), 6) || 
                RPAD(r.creator_username, 15) || 
                RPAD(r.turn_to_move, 4) || 
                r.board_position
            );
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('... Задачи, соответствующие критериям, не найдены. ...');
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при показе задач: ' || SQLERRM);
    END show_puzzles;
    
    PROCEDURE show_my_puzzles(p_difficulty IN NUMBER DEFAULT NULL) IS
        v_player_id players.player_id%TYPE;
        v_found     BOOLEAN := FALSE;
        
        -- Курсор для выборки СВОИХ задач
        CURSOR c_my_puzzles IS
            SELECT 
                puz.puzzle_id,
                puz.difficulty_level,
                puz.moves_to_solve,
                puz.board_position,
                puz.turn_to_move
            FROM puzzles puz
            WHERE 
                puz.created_by_player_id = v_player_id
                AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        DBMS_OUTPUT.PUT_LINE('--- Мои Созданные Задачи ---');
        IF p_difficulty IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE(' (Фильтр по Сложности: ' || p_difficulty || ')');
        END IF;

        DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || RPAD('Сложность', 10) || RPAD('Ходов', 6) || RPAD('Ход', 4) || 'Позиция (RLE)');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 5, '-') || ' ' || RPAD('-', 10, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

        FOR r IN c_my_puzzles LOOP
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.puzzle_id, 5) || 
                RPAD(r.difficulty_level, 10) || 
                RPAD(NVL(TO_CHAR(r.moves_to_solve), 'N/A'), 6) || 
                RPAD(r.turn_to_move, 4) || 
                r.board_position
            );
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('... У вас нет созданных задач' || 
                CASE WHEN p_difficulty IS NOT NULL THEN ' (Сложность: ' || p_difficulty || ')' ELSE '' END || '. ...');
        END IF;
    END show_my_puzzles;
    
    PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER) IS
        v_player_id players.player_id%TYPE;
        v_error_msg VARCHAR2(255);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        -- 1. Проверка активной сессии
        IF get_active_game(v_player_id) IS NOT NULL THEN
            v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы удалить задачу.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        -- 2. Попытка удаления
        BEGIN
            DELETE FROM puzzles
            WHERE puzzle_id = p_puzzle_id
              AND created_by_player_id = v_player_id;
              
            IF SQL%ROWCOUNT = 0 THEN
                -- Проверяем, почему не удалилось
                DECLARE
                    v_count PLS_INTEGER;
                BEGIN
                    SELECT 1 INTO v_count FROM puzzles WHERE puzzle_id = p_puzzle_id;
                    -- Если найдено, значит, не принадлежит нам
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
            WHEN OTHERS THEN -- Обработка ошибки Foreign Key
                ROLLBACK;
                IF SQLCODE = -2292 THEN -- ORA-02292: integrity constraint (fk_daily_puzzles_puzzle)
                    v_error_msg := 'Ошибка: Невозможно удалить задачу. Она используется (или использовалась) как "Задача Дня".';
                ELSE
                    v_error_msg := 'Ошибка при удалении: ' || SQLERRM;
                END IF;
                p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 255));
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
        END;
    END delete_my_puzzle;
    
    PROCEDURE show_daily_puzzle IS
        v_today DATE := TRUNC(SYSDATE);
        v_puzzle_info rec_daily_puzzle_info; -- Используем тип из PKS
        v_player_id players.player_id%TYPE;
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        BEGIN
            -- Выбираем информацию о сегодняшней задаче
            SELECT 
                dp.puzzle_date,
                p.puzzle_id,
                p.difficulty_level,
                p.moves_to_solve,
                p.turn_to_move,
                p.board_position
            INTO v_puzzle_info
            FROM daily_puzzles dp
            JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
            WHERE dp.puzzle_date = v_today;
            
            -- Выводим, если найдено
            DBMS_OUTPUT.PUT_LINE('--- Задача Дня (' || TO_CHAR(v_today, 'DD.MM.YYYY') || ') ---');
            DBMS_OUTPUT.PUT_LINE('ID Задачи:   ' || v_puzzle_info.puzzle_id);
            DBMS_OUTPUT.PUT_LINE('Сложность:   ' || v_puzzle_info.difficulty_level);
            DBMS_OUTPUT.PUT_LINE('Ходов:       ' || NVL(TO_CHAR(v_puzzle_info.moves_to_solve), 'N/A'));
            DBMS_OUTPUT.PUT_LINE('Ход:         ' || v_puzzle_info.turn_to_move);
            DBMS_OUTPUT.PUT_LINE('Позиция:     ' || v_puzzle_info.board_position);
            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE('Для решения, вызовите: EXEC game_logic.start_daily_puzzle;');

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('Ошибка: Задача на ' || TO_CHAR(v_today, 'DD.MM.YYYY') || ' еще не назначена.');
                p_audit_log(NULL, NULL, p_event_msg => 'DAILY_PUZZLE_NOT_FOUND');
        END;
    END show_daily_puzzle;

    PROCEDURE info IS
        c_nl CONSTANT VARCHAR2(1) := CHR(10);
    BEGIN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle" (v1.2)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Это главная справка по пакету game_logic. ');
        DBMS_OUTPUT.PUT_LINE('Для корректной работы справки убедитесь, что у вас включен DBMS_OUTPUT.');
        DBMS_OUTPUT.PUT_LINE('---');
        
        DBMS_OUTPUT.PUT_LINE('## 1. НАЧАЛО ИГРЫ (CREATE_GAME)');
        DBMS_OUTPUT.PUT_LINE('Вы можете начать 3 типа сессий:');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  А. Игра против ИИ (PvE):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
        DBMS_OUTPUT.PUT_LINE('     (Сложность: ''E'' - Easy, ''M'' - Medium, ''H'' - Hard)');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Б. Открытая игра (PvP):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game; END;');
        DBMS_OUTPUT.PUT_LINE('     (Создает игру, к которой может присоединиться любой желающий)');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  В. Прямой вызов (PvP):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_opponent_username => ''BOB''); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  * Выбор цвета (для PvP/PvE):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_player_color => ''W''); END; -- (Играть за Белых)');
        DBMS_OUTPUT.PUT_LINE('     (Если не указать, цвет будет выбран случайно)');
        DBMS_OUTPUT.PUT_LINE(c_nl);

        DBMS_OUTPUT.PUT_LINE('## 2. ПРИСОЕДИНЕНИЕ К ИГРЕ (JOIN_GAME)');
        DBMS_OUTPUT.PUT_LINE('Если вас вызвали (или вы нашли ID открытой игры):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.join_game(p_game_id => 123); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);

        DBMS_OUTPUT.PUT_LINE('## 3. ИГРОВОЙ ПРОЦЕСС');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  А. Сделать ход (make_move):');
        DBMS_OUTPUT.PUT_LINE('     Используйте стандартную шашечную нотацию.');
        DBMS_OUTPUT.PUT_LINE('     Тихий ход: ''a3-b4''');
        DBMS_OUTPUT.PUT_LINE('     Взятие:    ''a3:c5'' (двоеточие обязательно)');
        DBMS_OUTPUT.PUT_LINE('     Multi-взятие: ''a3:c5:e7''');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.make_move(p_move_notation => ''c3-d4''); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Б. Посмотреть доску (print_active_board):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  В. Сдаться (resign_game):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.resign_game; END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Г. Отменить ожидающую игру (cancel_game):');
        DBMS_OUTPUT.PUT_LINE('     (Работает, только если игра в статусе ''O'' или ''C'')');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.cancel_game; END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Д. Ничья (draw):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''O''); END; -- (O = Offer / Предложить)');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''A''); END; -- (A = Accept / Принять)');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''C''); END; -- (C = Cancel-Decline / Отменить-Отклонить)');
        DBMS_OUTPUT.PUT_LINE(c_nl);

        DBMS_OUTPUT.PUT_LINE('## 4. МАТЧИ (СЕРИИ ИГР)');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  А. Создать матч (до N побед):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_match(p_opponent_username => ''BOB'', p_games_to_win => 3); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Б. Присоединиться к матчу:');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.join_match(p_match_id => 456); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  В. Сдаться в матче (досрочно):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('## 5. ЗАДАЧИ (PUZZLES)');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  А. Посмотреть список задач:');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles; END;');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles(p_difficulty => 1); END;');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles(p_puzzle_id => 101); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Б. Задача Дня:');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_daily_puzzle; END;');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.start_daily_puzzle; END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  В. Начать любую задачу (по ID):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_puzzle_id => 101); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Г. Управление своими задачами:');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_my_puzzles; END;');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.delete_my_puzzle(p_puzzle_id => 102); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);

        DBMS_OUTPUT.PUT_LINE('## 6. ПРОСМОТР ИГР (ЗРИТЕЛЬ И РЕПЛЕИ)');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  А. Смотреть АКТИВНУЮ игру (Режим Зрителя):');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.print_active_board(p_username => ''BOB''); END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  Б. Выйти из режима Зрителя:');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.stop_watching; END;');
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('  В. Смотреть ЗАВЕРШЕННУЮ игру (Реплей):');
        DBMS_OUTPUT.PUT_LINE('     (Этот вызов создает сессию и показывает N первых ходов)');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 5); END;');
        DBMS_OUTPUT.PUT_LINE('     (Повторный вызов покажет следующие 5 ходов и т.д.)');
        DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 5); END;');
        DBMS_OUTPUT.PUT_LINE('     (Сессия реплея сбрасывается через 30 мин или при вызове stop_watching)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Для повторного вывода этой справки: BEGIN game_logic.info; END;');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
    END info;

     
--------------------------------------------------------------------------------
BEGIN -- Package Initialization Block
    -- Больше нет нужды в статической инициализации.
    -- Карта будет создаваться "на лету" при первом вызове.
    NULL;
END game_logic;