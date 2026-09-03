PROCEDURE cancel_game IS
    v_game_id   NUMBER;
    v_player_id players.player_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
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