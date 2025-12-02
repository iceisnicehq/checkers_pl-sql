PROCEDURE join_game(p_game_id IN NUMBER) IS
    v_game             games%ROWTYPE;
    v_player_id        players.player_id%TYPE;
    v_active_game_id   NUMBER;
    v_error_msg        VARCHAR2(2000);
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

    IF v_game.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Нельзя присоединиться к этой игре (ID: ' || p_game_id || ', статус: '|| v_game.status || ').';
        p_audit_log(v_player_id, p_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    DECLARE
        v_creator_id players.player_id%TYPE;
    BEGIN

        IF v_game.creator_player_color = 'W' THEN
            v_creator_id := v_game.player_white_id;
        ELSE
            v_creator_id := v_game.player_black_id;
        END IF;

        IF v_player_id = v_creator_id THEN
            v_error_msg := 'Нельзя присоединиться к собственной игре (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        IF v_game.status = 'C' THEN
            IF v_game.player_white_id IS NOT NULL AND v_game.player_black_id IS NOT NULL THEN

                IF v_player_id NOT IN (v_game.player_white_id, v_game.player_black_id) THEN
                    v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                    p_audit_log(v_player_id, p_game_id, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    ROLLBACK; 
                    RETURN;
                END IF;
            END IF;
        END IF;
    END;

    IF v_game.status = 'O' THEN

        v_active_game_id := get_active_game(v_player_id);
        IF v_active_game_id IS NOT NULL AND v_active_game_id != p_game_id THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET player_white_id = NVL(v_game.player_white_id, v_player_id),
            player_black_id = NVL(v_game.player_black_id, v_player_id),
            status          = 'A',
            start_time      = SYSDATE,
            time_white_remaining_sec = time_limit_game_sec,
            time_black_remaining_sec = time_limit_game_sec
        WHERE game_id = p_game_id;
    ELSE

        UPDATE games
        SET status                  = 'A',
            start_time              = SYSDATE,
            time_white_remaining_sec = time_limit_game_sec,
            time_black_remaining_sec = time_limit_game_sec
        WHERE game_id = p_game_id;
    END IF;

    BEGIN
        DECLARE
            v_time_limit_game NUMBER;
            v_job_name        VARCHAR2(128);
            v_current_turn    CHAR(1);
            v_time_remaining  NUMBER;
        BEGIN
            SELECT time_limit_game_sec, current_turn,
                   CASE current_turn WHEN 'W' THEN time_white_remaining_sec ELSE time_black_remaining_sec END
            INTO v_time_limit_game, v_current_turn, v_time_remaining
            FROM games
            WHERE game_id = p_game_id;
            
            IF v_time_limit_game IS NOT NULL AND v_time_remaining IS NOT NULL THEN
                v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;

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
                    start_date => SYSTIMESTAMP + (GREATEST(1, v_time_remaining) / 86400),
                    enabled    => TRUE,
                    auto_drop  => TRUE,
                    comments   => 'Game timeout job for game ' || p_game_id
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END;
    
    p_audit_log(v_player_id, p_game_id, 'JOIN_GAME');

    IF v_game.match_id IS NOT NULL THEN
        DECLARE
            v_match matches%ROWTYPE;
        BEGIN
            SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;
            DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || ' (часть матча ID ' || v_game.match_id || ', Best of ' || v_match.games_to_win || ').');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
        END;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
    END IF;
    
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при присоединении к игре: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 2000));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END join_game;