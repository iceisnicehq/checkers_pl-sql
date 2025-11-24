-- @function get_active_game
-- @brief Finds ANY active session (game OR spectating).
-- @return game_id if the player is busy (playing or watching), otherwise NULL.
-- @dependencies:
--   - games (table)
--   - spectators (table)

FUNCTION get_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
    v_game_id games.game_id%TYPE;
BEGIN
    -- 1. Сначала ищем, не ИГРАЕТ ли пользователь
    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM games
        WHERE (player_white_id = p_user_id OR player_black_id = p_user_id)
          AND status IN ('A', 'O', 'C'); -- Активна, Открыта, Вызов
        
        -- Если нашли, он занят. Возвращаем ID.
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL; -- Не играет. Проверяем, не смотрит ли он.
    END;

    -- 2. Если не играет, ищем, не СМОТРИТ ли он
    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM spectators
        WHERE player_id = p_user_id
          AND left_at IS NULL
          AND ROWNUM = 1;
        
        -- Если нашли, он тоже занят.
        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Не играет и не смотрит. Он свободен.
            RETURN NULL;
    END;
END get_active_game;