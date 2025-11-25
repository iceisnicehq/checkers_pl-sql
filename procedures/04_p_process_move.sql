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

    UPDATE games
    SET current_turn          = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
        draw_offer_status     = NULL, 
        draw_offered_by_color = NULL, 
        draw_offered_at       = NULL
    WHERE game_id = p_game_id;

    INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
    VALUES (p_game_id, v_move_count, p_move_notation, v_chosen_move.is_capture, v_new_board_encoded);
    
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
            SELECT COUNT(*) INTO v_repetition_count FROM game_moves WHERE game_id = p_game_id AND board_position = v_new_board_encoded;
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
        END IF;
    END;
    
    COMMIT;
END p_process_move;