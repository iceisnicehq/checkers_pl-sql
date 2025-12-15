PROCEDURE create_puzzle(
    p_board_position   IN VARCHAR2,
    p_turn_to_move     IN CHAR,
    p_moves_to_solve   IN NUMBER DEFAULT NULL,
    p_difficulty_level IN CHAR DEFAULT 'M',
    p_solution          IN VARCHAR2 DEFAULT NULL
) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(2000);
    
    v_single_line_board VARCHAR2(200) := '';
    v_board_size        NUMBER;
    v_rule_id           game_rules.rule_id%TYPE;
    v_encoded_board     VARCHAR2(100);
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
        -- Удаляем пробелы из RLE строки
        v_encoded_board := REGEXP_REPLACE(p_board_position, '[[:space:]]', '');
        
        -- Декодируем RLE в развернутую строку для валидации
        v_single_line_board := decode_board(v_encoded_board);
        
        IF LENGTH(v_single_line_board) > 200 THEN
            v_error_msg := 'Ошибка: Размер доски превышает допустимый предел.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        IF LENGTH(v_single_line_board) = 64 THEN
            v_board_size := 8;
        ELSIF LENGTH(v_single_line_board) = 100 THEN
            v_board_size := 10;
        ELSE
            v_error_msg := 'Ошибка: Неверный размер доски. Ожидалось 64 (8x8) или 100 (10x10) символов, получено: ' || LENGTH(v_single_line_board);
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        IF REGEXP_LIKE(v_single_line_board, '[^wWbB+]') THEN
            v_error_msg := 'Ошибка: Доска содержит недопустимые символы. Разрешены только: w, W, b, B, +.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        IF INSTR(v_single_line_board, 'w') = 0 AND INSTR(v_single_line_board, 'W') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной белой фигуры (w, W).';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        IF INSTR(v_single_line_board, 'b') = 0 AND INSTR(v_single_line_board, 'B') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной черной фигуры (b, B).';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        p_init_board_map(v_board_size);
        
        FOR i IN 1 .. LENGTH(v_single_line_board) LOOP
            DECLARE
                v_piece CHAR(1) := SUBSTR(v_single_line_board, i, 1);
                v_field rec_board_field;
            BEGIN

                IF v_piece IN ('w', 'W', 'b', 'B') THEN
                    IF NOT g_map_by_idx.EXISTS(i) THEN
                        v_error_msg := 'Ошибка: Недопустимый индекс позиции: ' || i;
                        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        RETURN;
                    END IF;
                    
                    v_field := g_map_by_idx(i);
                    
                    -- Проверка: фигура должна быть на темной клетке
                    -- В шашках темные клетки - это те, где (row + col) четное
                    IF MOD(v_field.row_num + v_field.col_num, 2) != 0 THEN
                        v_error_msg := 'Ошибка: Фигура на позиции ' || v_field.notation || 
                                     ' (индекс ' || i || ', строка ' || v_field.row_num || ', столбец ' || v_field.col_num || 
                                     ') находится на светлой клетке. В шашках фигуры могут быть только на темных клетках.';
                        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        RETURN;
                    END IF;
                END IF;
            END;
        END LOOP;

        SELECT rule_id INTO v_rule_id
        FROM game_rules
        WHERE board_size = v_board_size
        AND ROWNUM = 1;

        -- v_encoded_board уже содержит RLE формат, сохраняем как есть
        
        INSERT INTO puzzles (
            board_position,
            rule_id,
            turn_to_move,
            moves_to_solve,
            difficulty_level,
            created_by_player_id,
            solution
        ) VALUES (
            v_encoded_board,
            v_rule_id,
            UPPER(p_turn_to_move),
            p_moves_to_solve,
            p_difficulty_level,
            v_player_id,
            p_solution
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
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 2000));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;

END create_puzzle;