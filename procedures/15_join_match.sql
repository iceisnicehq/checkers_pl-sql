-- @procedure join_match
-- @brief Allows a player to join an open or challenged match.
-- @dependencies:
--   - players (table)
--   - matches (table)
--   - games (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - join_game (procedure)

PROCEDURE join_match(p_match_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_match     matches%ROWTYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
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
    
    IF v_match.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Матч (ID: ' || p_match_id || ') уже начат или завершен (Статус: ' || v_match.status || ').';
        p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
    
    join_game(v_game.game_id);
    
    DECLARE
        v_game_status CHAR(1);
    BEGIN
        SELECT status INTO v_game_status 
        FROM games 
        WHERE game_id = v_game.game_id;
        
        IF v_game_status = 'A' THEN
            UPDATE matches
            SET status = 'A'
            WHERE match_id = p_match_id;
            
            DBMS_OUTPUT.PUT_LINE('Вы присоединились к матчу (ID: ' || p_match_id || '). Начинается первая игра (ID: ' || v_game.game_id || ').');
            p_audit_log(v_player_id, v_game.game_id, 'MATCH_JOINED');
            COMMIT;
        ELSE
            ROLLBACK;
        END IF;
    END;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END join_match;