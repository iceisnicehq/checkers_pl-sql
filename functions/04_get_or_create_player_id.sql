-- @function get_or_create_player_id
-- @brief Retrieves the player_id for a given username, creating the player if it doesn't exist.
-- @dependencies:
--   - players (table)

FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
    v_player_id players.player_id%TYPE;
BEGIN
    BEGIN
        SELECT player_id
        INTO v_player_id
        FROM players
        WHERE username = p_username;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO players (username)
            VALUES (p_username)
            RETURNING player_id INTO v_player_id;
    END;
    RETURN v_player_id;
END get_or_create_player_id;