-- @procedure cancel_game
-- @brief Cancels an open or challenged game.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

PROCEDURE cancel_game IS
    v_game_id   NUMBER;
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

    IF v_game.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Эту игру (ID: ' || v_game_id || ') нельзя отменить (статус '||v_game.status||'). Используйте resign_game, чтобы сдаться.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
           
    DELETE FROM games WHERE game_id = v_game_id;
    p_audit_log(v_player_id, v_game_id, 'CANCEL_GAME');
    DBMS_OUTPUT.PUT_LINE('Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при отмене игры: ' || SQLERRM;
        p_audit_log(v_player_id, v_game_id, SUBSTR(v_error_msg, 1, 100));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END cancel_game;