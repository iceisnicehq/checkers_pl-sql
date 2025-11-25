FUNCTION get_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
    v_game_id games.game_id%TYPE;
BEGIN
    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM games
        WHERE (player_white_id = p_user_id OR player_black_id = p_user_id)
          AND status IN ('A', 'O', 'C');
        
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
    END;

    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM spectators
        WHERE player_id = p_user_id
          AND left_at IS NULL
          AND ROWNUM = 1;
        
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END;
END get_active_game;
