CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_participations AS (
    SELECT player_white_id AS player_id, status, winner_player_id FROM games WHERE status IN ('V', 'D', 'T')
    UNION ALL
    SELECT player_black_id AS player_id, status, winner_player_id FROM games WHERE status IN ('V', 'D', 'T')
),
player_stats AS (
    SELECT
        player_id,
        COUNT(*) AS games_played,
        SUM(CASE WHEN winner_player_id = player_id THEN 1 ELSE 0 END) AS wins,
        SUM(CASE WHEN status = 'D' THEN 1 ELSE 0 END) AS draws,
        SUM(CASE WHEN status != 'D' AND (winner_player_id IS NULL OR winner_player_id != player_id) THEN 1 ELSE 0 END) AS losses
    FROM game_participations
    WHERE player_id IS NOT NULL
    GROUP BY player_id
)
SELECT
    p.username,
    ps.games_played,
    ps.wins,
    ps.losses,
    ps.draws,
    CASE
        WHEN ps.losses = 0 AND ps.wins > 0 THEN (ps.wins * 100.0)
        WHEN ps.losses = 0 AND ps.wins = 0 THEN 0.0
        ELSE ROUND((ps.wins * 1.0 / ps.losses) * 100, 2)
    END AS success_rate_percent
FROM
    player_stats ps
JOIN
    players p ON ps.player_id = p.player_id
ORDER BY
    success_rate_percent DESC, wins DESC;