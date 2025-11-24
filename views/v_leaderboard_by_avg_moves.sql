-- View для рейтинга по среднему числу ходов
CREATE OR REPLACE VIEW v_leaderboard_by_avg_moves AS
WITH game_participations AS (
    SELECT 
        player_white_id AS player_id, 
        'W' AS my_color, 
        status, 
        winner_player_color,
        (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves
    FROM games 
    WHERE status IN ('V', 'D', 'T')
    
    UNION ALL
    
    SELECT 
        player_black_id AS player_id, 
        'B' AS my_color, 
        status, 
        winner_player_color,
        (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves
    FROM games 
    WHERE status IN ('V', 'D', 'T')
),
player_avg_moves AS (
    SELECT
        player_id,
        COUNT(*) AS games_played,
        ROUND(AVG(total_moves), 2) AS avg_moves_per_game
    FROM game_participations
    WHERE player_id IS NOT NULL
    GROUP BY player_id
    HAVING COUNT(*) > 0
)
SELECT
    p.username,
    pam.games_played,
    pam.avg_moves_per_game
FROM
    player_avg_moves pam
JOIN
    players p ON pam.player_id = p.player_id
ORDER BY
    pam.avg_moves_per_game DESC, pam.games_played DESC;

COMMENT ON VIEW v_leaderboard_by_avg_moves IS 'Рейтинг игроков по среднему числу ходов в партии.';

