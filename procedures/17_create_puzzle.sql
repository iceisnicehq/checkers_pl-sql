PROCEDURE create_puzzle(
    p_board_position   IN CLOB,
    p_turn_to_move     IN CHAR,
    p_moves_to_solve   IN NUMBER DEFAULT NULL,
    p_difficulty_level IN CHAR DEFAULT 'M',
    p_solution          IN VARCHAR2 DEFAULT NULL
) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(2000);
    
    v_single_line_board VARCHAR2(200) := '';
    v_line              VARCHAR2(200);
    v_offset            NUMBER := 1;
    v_clob_len          NUMBER;
    v_line_break        NUMBER;
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
        v_clob_len := DBMS_LOB.getlength(p_board_position);

        WHILE v_offset <= v_clob_len LOOP
            v_line_break := DBMS_LOB.instr(p_board_position, c_nl, v_offset);
            
            IF v_line_break = 0 THEN

                v_line := DBMS_LOB.substr(p_board_position, v_clob_len - v_offset + 1, v_offset);
                v_offset := v_clob_len + 1;
            ELSE

                v_line := DBMS_LOB.substr(p_board_position, v_line_break - v_offset, v_offset);
                v_offset := v_line_break + 1;
            END IF;

            v_line := REGEXP_REPLACE(v_line, '[[:space:]]', '');
            
            IF LENGTH(v_line) > 0 THEN

                IF LENGTH(v_single_line_board) + LENGTH(v_line) > 200 THEN
                     v_error_msg := 'Ошибка: Размер доски превышает допустимый предел.';
                     p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                     DBMS_OUTPUT.PUT_LINE(v_error_msg);
                     RETURN;
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
                v_row PLS_INTEGER;
                v_col PLS_INTEGER;
                v_is_dark_square BOOLEAN;
            BEGIN

                IF v_piece IN ('w', 'W', 'b', 'B') THEN
                    IF NOT g_map_by_idx.EXISTS(i) THEN
                        v_error_msg := 'Ошибка: Недопустимый индекс позиции: ' || i;
                        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        RETURN;
                    END IF;
                    
                    v_field := g_map_by_idx(i);
                    v_row := v_field.row_num;
                    v_col := v_field.col_num;

                    v_is_dark_square := (MOD(v_row + v_col, 2) = 1);
                    
                    IF NOT v_is_dark_square THEN
                        v_error_msg := 'Ошибка: Фигура на позиции ' || v_field.notation || 
                                     ' (индекс ' || i || ', строка ' || v_row || ', столбец ' || v_col || 
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

        v_encoded_board := encode_board(v_single_line_board);
        
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