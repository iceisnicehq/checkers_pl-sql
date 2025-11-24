-- View для статистики игрока: свод побед/поражений/ничьих, средняя длина партии, завершения по времени
CREATE OR REPLACE VIEW v_player_stats AS
WITH game_participations AS (
    SELECT 
        g.game_id,
        CASE WHEN g.player_white_id = p_user.player_id THEN g.player_white_id ELSE g.player_black_id END AS player_id,
        g.status,
        g.winner_player_color,
        CASE WHEN g.player_white_id = p_user.player_id THEN 'W' ELSE 'B' END AS my_color,
        g.end_time,
        g.start_time,
        (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
        g.rule_id
    FROM games g
    JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
    WHERE g.status IN ('V', 'D', 'T', 'R')
      AND p_user.username = USER
)
SELECT
    gp.player_id,
    COUNT(*) AS games_played,
    SUM(CASE WHEN gp.status = 'D' THEN 1 ELSE 0 END) AS draws,
    SUM(CASE WHEN gp.winner_player_color = gp.my_color THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN gp.status != 'D' AND gp.winner_player_color IS NOT NULL AND gp.winner_player_color != gp.my_color THEN 1 ELSE 0 END) AS losses,
    SUM(CASE WHEN gp.status = 'T' THEN 1 ELSE 0 END) AS timeouts,
    ROUND(AVG(gp.total_moves), 2) AS avg_game_length,
    ROUND(AVG(CASE WHEN gp.end_time IS NOT NULL AND gp.start_time IS NOT NULL 
        THEN (gp.end_time - gp.start_time) * 24 * 60
        ELSE NULL END), 2) AS avg_game_duration_minutes,
    MIN(gp.start_time) AS first_game_date,
    MAX(gp.end_time) AS last_game_date
FROM game_participations gp
GROUP BY gp.player_id;

