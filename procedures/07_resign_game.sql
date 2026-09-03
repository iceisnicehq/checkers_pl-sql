PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N') IS
    v_game        games%ROWTYPE;
    v_player_id   players.player_id%TYPE;
    v_game_id     NUMBER;
    v_error_msg   VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(user);
    
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

    IF v_game.puzzle_id IS NOT NULL THEN
        p_drop_move_timeout_job(v_game_id);
        
        UPDATE games
        SET status = 'V',
            end_time = SYSDATE,
            puzzle_status = 'f'
        WHERE game_id = v_game_id;
        
        UPDATE spectators SET left_at = SYSDATE 
        WHERE game_id = v_game_id AND left_at IS NULL;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'QUIT_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('[OK] Вы вышли из попытки решения задачи (ID сессии: ' || v_game_id || ').');
        
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
            SET status              = 'R',
                winner_player_color = v_winner_color,
                end_time            = SYSDATE
            WHERE game_id = v_game_id;

            UPDATE spectators SET left_at = SYSDATE 
            WHERE game_id = v_game_id AND left_at IS NULL;

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
