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
    p_username      IN VARCHAR2 DEFAULT NULL,
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
        
    END IF;
    
    IF v_game_rec.game_id IS NULL THEN
         SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
    END IF;

    FOR i IN 1 .. p_moves_to_show LOOP
        BEGIN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num;
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE = -8004 THEN
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