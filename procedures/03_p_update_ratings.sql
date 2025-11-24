-- @procedure p_update_ratings
-- @brief Updates player ratings after a game is finished.
-- @dependencies:
--   - (none)

PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
BEGIN
    -- TODO: Реализовать логику обновления Elo/статистики
    NULL;
END p_update_ratings;