-- View для рейтингов/топа: все игроки, все сезоны
CREATE OR REPLACE VIEW v_player_ratings AS
WITH game_participations AS (
    SELECT 
        g.game_id,
        g.player_white_id AS player_id, 
        'W' AS my_color, 
        g.status, 
        g.winner_player_color,
        (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
        ROUND((g.end_time - g.start_time) * 24 * 60, 2) AS duration_minutes
    FROM games g
    WHERE g.status IN ('V', 'D', 'T', 'R')
      AND g.ai_difficulty IS NULL -- Только PvP игры
    
    UNION ALL
    
    SELECT 
        g.game_id,
        g.player_black_id AS player_id, 
        'B' AS my_color, 
        g.status, 
        g.winner_player_color,
        (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
        ROUND((g.end_time - g.start_time) * 24 * 60, 2) AS duration_minutes
    FROM games g
    WHERE g.status IN ('V', 'D', 'T', 'R')
      AND g.ai_difficulty IS NULL -- Только PvP игры
),
player_stats AS (
    SELECT
        gp.player_id,
        COUNT(*) AS games_played,
        SUM(CASE WHEN gp.winner_player_color = gp.my_color THEN 1 ELSE 0 END) AS wins,
        SUM(CASE WHEN gp.status = 'D' THEN 1 ELSE 0 END) AS draws,
        SUM(CASE WHEN gp.status != 'D' AND gp.winner_player_color IS NOT NULL AND gp.winner_player_color != gp.my_color THEN 1 ELSE 0 END) AS losses,
        ROUND(AVG(gp.total_moves), 2) AS avg_moves_per_game,
        ROUND(AVG(gp.duration_minutes), 2) AS avg_game_duration_minutes
    FROM game_participations gp
    WHERE gp.player_id IS NOT NULL
    GROUP BY gp.player_id
)
SELECT
    p.username AS player_name,
    s.season_id,
    s.season_name,
    gr.rule_id,
    gr.rule_name,
    pr.rating,
    NVL(ps.wins, 0) AS wins,
    NVL(ps.draws, 0) AS draws,
    NVL(ps.losses, 0) AS losses,
    NVL(ps.avg_moves_per_game, 0) AS avg_moves_per_game,
    NVL(ps.avg_game_duration_minutes, 0) AS avg_game_duration_minutes
FROM player_ratings pr
JOIN players p ON pr.player_id = p.player_id
JOIN seasons s ON pr.season_id = s.season_id
JOIN game_rules gr ON pr.rule_id = gr.rule_id
LEFT JOIN player_stats ps ON ps.player_id = pr.player_id
ORDER BY s.season_id DESC, pr.rating DESC;
