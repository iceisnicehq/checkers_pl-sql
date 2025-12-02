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
    v_decoded_board     VARCHAR2(100);
    v_new_board_decoded VARCHAR2(100);
    v_new_board_encoded VARCHAR2(100);

    v_time_delta_sec        NUMBER;
    v_current_player_time   NUMBER;
    v_next_player_time      NUMBER;
    
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;

    SELECT r.board_size INTO v_board_size 
    FROM game_rules r 
    WHERE r.rule_id = v_game.rule_id;
    
    p_init_board_map(v_board_size);

    v_decoded_board := f_get_current_board_position(p_game_id, v_game.rule_id);

    IF v_game.ai_difficulty IS NOT NULL THEN
        v_player_color := v_game.current_turn;
    ELSE
        IF v_game.player_white_id = p_player_id THEN
            v_player_color := 'W';
        ELSE
            v_player_color := 'B';
        END IF;
    END IF;

    IF v_game.time_limit_game_sec IS NOT NULL THEN
        DECLARE
            v_player_time_remaining NUMBER;
            v_last_move_time        DATE;
            v_current_time          DATE := SYSDATE;
        BEGIN

            IF v_player_color = 'W' THEN
                v_player_time_remaining := v_game.time_white_remaining_sec;
            ELSE
                v_player_time_remaining := v_game.time_black_remaining_sec;
            END IF;

            IF v_player_time_remaining IS NULL THEN
                v_error_msg := 'Время игрока не инициализировано.';
                p_audit_log(p_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK;
                RETURN;
            END IF;

            BEGIN
                SELECT MAX(move_timestamp) INTO v_last_move_time
                FROM game_moves
                WHERE game_id = p_game_id;
                
                IF v_last_move_time IS NULL THEN
                    v_last_move_time := v_game.start_time;
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_last_move_time := v_game.start_time;
            END;

            v_time_delta_sec := (v_current_time - v_last_move_time) * 86400;

            v_current_player_time := v_player_time_remaining - v_time_delta_sec;

            IF v_current_player_time <= 0 THEN
                p_finish_game(
                    p_game_id      => p_game_id,
                    p_status       => 'T',
                    p_winner_color => CASE WHEN v_player_color = 'W' THEN 'B' ELSE 'W' END,
                    p_audit_event  => 'GAME_TIMEOUT'
                );
                p_status_message := 'Игра завершена по таймауту. У ' || 
                                   CASE WHEN v_player_color = 'W' THEN 'белых' ELSE 'черных' END || 
                                   ' закончилось время.';
                RETURN;
            END IF;
        END;
    END IF;

    v_all_legal_moves := find_all_player_moves(v_decoded_board, v_player_color, v_game.rule_id);

    IF v_all_legal_moves.COUNT = 0 THEN
        p_finish_game(
            p_game_id       => p_game_id,
            p_status        => 'V',
            p_winner_color  => CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            p_puzzle_status => CASE WHEN v_game.puzzle_id IS NOT NULL THEN 'f' ELSE NULL END,
            p_audit_event   => 'GAME_LOST_NO_MOVES',
            p_player_id     => p_player_id
        );
        p_status_message := 'Ходов нет. Вы проиграли!';
        RETURN;
    END IF;

    FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
        DECLARE
            v_notation VARCHAR2(100) := f_move_to_notation(v_all_legal_moves(i), v_board_size);
        BEGIN
            IF LOWER(p_move_notation) = v_notation THEN
                v_chosen_move   := v_all_legal_moves(i);
                v_is_move_valid := TRUE;
                EXIT;
            END IF;
        END;
    END LOOP;

    IF NOT v_is_move_valid THEN
        IF v_all_legal_moves(1).is_capture = 'Y' THEN
            DECLARE
                v_notation_str VARCHAR2(100);
            BEGIN
                v_error_msg := 'Неверный ход. Взятие обязательно! Доступные варианты: ';
                FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
                    v_notation_str := f_move_to_notation(v_all_legal_moves(i), v_board_size);
                    v_error_msg := v_error_msg || v_notation_str || ' ';
                END LOOP;
                v_error_msg := RTRIM(v_error_msg);
            END;
        ELSE
            v_error_msg := 'Нелегальный ход: "' || p_move_notation || '".';
        END IF;

        p_audit_log(
            p_player_id => p_player_id, 
            p_game_id   => p_game_id, 
            p_event_msg => SUBSTR(v_error_msg, 1, 2000)
        );
        
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        p_status_message := v_error_msg;
        ROLLBACK;
        RETURN;
    END IF;

    v_new_board_decoded := apply_move_to_board(v_decoded_board, v_chosen_move, v_player_color);

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

    IF v_game.time_limit_game_sec IS NOT NULL THEN
        DECLARE
            v_next_turn_color       CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
            v_job_name              VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
        BEGIN

            UPDATE games
            SET time_white_remaining_sec = CASE WHEN v_player_color = 'W' 
                                                THEN v_current_player_time 
                                                ELSE time_white_remaining_sec 
                                           END,
                time_black_remaining_sec = CASE WHEN v_player_color = 'B' 
                                                THEN v_current_player_time 
                                                ELSE time_black_remaining_sec 
                                           END
            WHERE game_id = p_game_id;

            SELECT CASE WHEN v_next_turn_color = 'W' 
                       THEN time_white_remaining_sec 
                       ELSE time_black_remaining_sec 
                  END
            INTO v_next_player_time
            FROM games
            WHERE game_id = p_game_id;

            BEGIN
                DBMS_SCHEDULER.SET_ATTRIBUTE(
                    name      => v_job_name,
                    attribute => 'start_date',
                    value     => SYSTIMESTAMP + (GREATEST(1, v_next_player_time) / 86400)
                );
            EXCEPTION
                WHEN OTHERS THEN

                    DBMS_SCHEDULER.CREATE_JOB(
                        job_name   => v_job_name,
                        job_type   => 'PLSQL_BLOCK',
                        job_action => 'DECLARE
                                v_game games%ROWTYPE;
                                v_loser_color CHAR(1);
                            BEGIN
                                BEGIN
                                    SELECT * INTO v_game FROM games WHERE game_id = ' || p_game_id || ' FOR UPDATE;
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        RETURN;
                                END;
                                
                                IF v_game.status != ''A'' THEN
                                    RETURN;
                                END IF;
                                
                                v_loser_color := v_game.current_turn;
                                
                                UPDATE games
                                SET status = ''T'',
                                    end_time = SYSDATE,
                                    winner_player_color = CASE v_loser_color WHEN ''W'' THEN ''B'' ELSE ''W'' END
                                WHERE game_id = ' || p_game_id || ';
                                
                                UPDATE spectators SET left_at = SYSDATE 
                                WHERE game_id = ' || p_game_id || ' AND left_at IS NULL;
                                
                                game_logic.p_update_ratings(' || p_game_id || ');
                                game_logic.p_audit_log(NULL, ' || p_game_id || ', ''GAME_TIMEOUT'');
                                COMMIT;
                            EXCEPTION
                                WHEN OTHERS THEN NULL;
                            END;',
                        start_date => SYSTIMESTAMP + (GREATEST(1, v_next_player_time) / 86400),
                        enabled    => TRUE,
                        auto_drop  => TRUE,
                        comments   => 'Game timeout job for game ' || p_game_id
                    );
            END;
        END;
    ELSIF v_game.time_limit_move_sec IS NOT NULL THEN

        DECLARE
            v_job_name VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
        BEGIN
            DBMS_SCHEDULER.SET_ATTRIBUTE(
                name      => v_job_name,
                attribute => 'start_date',
                value     => SYSTIMESTAMP + (v_game.time_limit_move_sec / 86400)
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END IF;
    
    IF p_player_id IS NULL THEN
        p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
    ELSE
        p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
    END IF;

    DECLARE
        v_next_turn_color       CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
        v_next_player_moves     t_move_list;
        v_opponent_pieces_exist BOOLEAN := FALSE;
        v_repetition_count      NUMBER;
    BEGIN

        IF v_next_turn_color = 'W' THEN
            v_opponent_pieces_exist := INSTR(v_new_board_decoded, c_white_man) > 0 OR INSTR(v_new_board_decoded, c_white_king) > 0;
        ELSE
            v_opponent_pieces_exist := INSTR(v_new_board_decoded, c_black_man) > 0 OR INSTR(v_new_board_decoded, c_black_king) > 0;
        END IF;

        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_puzzle_end_board VARCHAR2(100);
                v_puzzle_moves_to_solve NUMBER;
                v_puzzle_solution VARCHAR2(2000);
                v_current_move_count NUMBER;
                v_encoded_current_board VARCHAR2(100);
                v_solution_msg VARCHAR2(2000);
            BEGIN
                SELECT end_board_state, moves_to_solve, solution
                INTO v_puzzle_end_board, v_puzzle_moves_to_solve, v_puzzle_solution
                FROM puzzles
                WHERE puzzle_id = v_game.puzzle_id;

                v_current_move_count := v_move_count;
                v_encoded_current_board := encode_board(v_new_board_decoded);

                IF v_puzzle_end_board IS NULL THEN

                    IF NOT v_opponent_pieces_exist THEN

                        IF v_puzzle_moves_to_solve IS NOT NULL AND v_current_move_count > v_puzzle_moves_to_solve THEN
                            v_solution_msg := 'Вы решили задачу за ' || v_current_move_count || ' ход(ов), но более оптимальное решение за ' || v_puzzle_moves_to_solve || ' хода(ов): ' || NVL(v_puzzle_solution, 'не указано');
                        ELSE
                            v_solution_msg := 'Поздравляем! Вы решили задачу за ' || v_current_move_count || ' хода(ов)!';
                        END IF;
                        
                        p_finish_game(
                            p_game_id       => p_game_id,
                            p_status        => 'V',
                            p_winner_color  => v_player_color,
                            p_puzzle_status => 's',
                            p_audit_event   => 'PUZZLE_SOLVED',
                            p_player_id     => p_player_id
                        );
                        p_status_message := p_status_message || ' Победа! У противника не осталось фигур.' || c_nl || v_solution_msg;
                        RETURN;
                    END IF;

                    DECLARE
                        v_next_turn_color_puzzle CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
                        v_next_player_moves_puzzle t_move_list;
                    BEGIN
                        v_next_player_moves_puzzle := find_all_player_moves(v_new_board_decoded, v_next_turn_color_puzzle, v_game.rule_id);
                        IF v_next_player_moves_puzzle.COUNT = 0 THEN

                            IF v_puzzle_moves_to_solve IS NOT NULL AND v_current_move_count > v_puzzle_moves_to_solve THEN
                                v_solution_msg := 'Вы решили задачу за ' || v_current_move_count || ' ход(ов), но более оптимальное решение за ' || v_puzzle_moves_to_solve || ' хода(ов): ' || NVL(v_puzzle_solution, 'не указано');
                            ELSE
                                v_solution_msg := 'Поздравляем! Вы решили задачу за ' || v_current_move_count || ' хода(ов)!';
                            END IF;
                            
                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'V',
                                p_winner_color  => v_player_color,
                                p_puzzle_status => 's',
                                p_audit_event   => 'PUZZLE_SOLVED',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Победа! Противник заблокирован.' || c_nl || v_solution_msg;
                            RETURN;
                        END IF;
                    END;
                ELSE

                    IF v_puzzle_moves_to_solve IS NOT NULL THEN
                        IF v_encoded_current_board = v_puzzle_end_board THEN

                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'D',
                                p_puzzle_status => 's',
                                p_audit_event   => 'PUZZLE_SOLVED_DRAW',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Ничья! Достигнута целевая позиция. Задача решена!';
                            RETURN;
                        ELSE

                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'D',
                                p_puzzle_status => 'f',
                                p_audit_event   => 'PUZZLE_FAILED_DRAW',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Ничья! Достигнуто ' || v_puzzle_moves_to_solve || ' ход(ов), но целевая позиция не достигнута. Задача не решена.';
                            RETURN;
                        END IF;
                    END IF;
                END IF;
            END;
        END IF;
        
        IF NOT v_opponent_pieces_exist THEN
            p_finish_game(
                p_game_id       => p_game_id,
                p_status        => 'V',
                p_winner_color  => v_player_color,
                p_audit_event   => 'WIN_NO_PIECES',
                p_player_id     => p_player_id
            );
            p_status_message := p_status_message || ' Победа! У противника не осталось фигур.';
            RETURN;
        END IF;

        v_next_player_moves := find_all_player_moves(v_new_board_decoded, v_next_turn_color, v_game.rule_id);
        IF v_next_player_moves.COUNT = 0 THEN
            p_finish_game(
                p_game_id       => p_game_id,
                p_status        => 'V',
                p_winner_color  => v_player_color,
                p_audit_event   => 'WIN_PAT',
                p_player_id     => p_player_id
            );
            p_status_message := p_status_message || ' Победа! Противник заблокирован.';
            RETURN;
        END IF;

        IF v_game.draw_moves_limit IS NOT NULL THEN
            DECLARE
                v_moves_without_capture PLS_INTEGER := 0;
                v_last_capture_move PLS_INTEGER := 0;
            BEGIN

                SELECT NVL(MAX(move_number), 0) INTO v_last_capture_move
                FROM game_moves
                WHERE game_id = p_game_id AND is_capture = 'Y';

                SELECT COUNT(*) INTO v_moves_without_capture
                FROM game_moves
                WHERE game_id = p_game_id
                  AND move_number > v_last_capture_move
                  AND is_capture = 'N';

                IF v_chosen_move.is_capture = 'N' THEN
                    v_moves_without_capture := v_moves_without_capture + 1;
                END IF;

                IF v_moves_without_capture >= v_game.draw_moves_limit THEN
                    p_finish_game(
                        p_game_id      => p_game_id,
                        p_status       => 'D',
                        p_audit_event  => 'DRAW_MOVES_LIMIT'
                    );
                    p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия (' || v_game.draw_moves_limit || ').';
                    RETURN;
                END IF;
            END;
        END IF;

        IF v_game.enable_pos_repetition_draw = 'Y' THEN

            DECLARE
                v_next_turn_after_move CHAR(1) := CASE WHEN MOD(v_move_count, 2) = 1 THEN 'B' ELSE 'W' END;
            BEGIN
                SELECT COUNT(*) INTO v_repetition_count 
                FROM game_moves 
                WHERE game_id = p_game_id 
                  AND board_position = v_new_board_encoded
                  AND CASE WHEN MOD(move_number, 2) = 1 THEN 'B' ELSE 'W' END = v_next_turn_after_move;
                  
                IF v_repetition_count >= 2 THEN
                    p_finish_game(
                        p_game_id      => p_game_id,
                        p_status       => 'D',
                        p_audit_event  => 'DRAW_REPETITION'
                    );
                    p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.';
                    RETURN;
                END IF;
            END;
        END IF;
    END;
    
    COMMIT;
END p_process_move;