CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_participations AS (
    -- Выборка для БЕЛЫХ
    SELECT 
        player_white_id AS player_id, 
        'W' AS my_color, 
        status, 
        winner_player_color 
    FROM games 
    WHERE status IN ('V', 'D', 'T')
    
    UNION ALL
    
    -- Выборка для ЧЕРНЫХ
    SELECT 
        player_black_id AS player_id, 
        'B' AS my_color, 
        status, 
        winner_player_color 
    FROM games 
    WHERE status IN ('V', 'D', 'T')
),
player_stats AS (
    SELECT
        player_id,
        COUNT(*) AS games_played,
        
        -- Победа: если цвет победителя совпадает с моим цветом
        SUM(CASE WHEN winner_player_color = my_color THEN 1 ELSE 0 END) AS wins,
        
        -- Ничья
        SUM(CASE WHEN status = 'D' THEN 1 ELSE 0 END) AS draws,
        
        -- Поражение: не ничья, есть победитель, и цвет победителя НЕ мой
        SUM(CASE WHEN status != 'D' AND (winner_player_color IS NOT NULL AND winner_player_color != my_color) THEN 1 ELSE 0 END) AS losses
    FROM game_participations
    WHERE player_id IS NOT NULL -- Исключаем ИИ
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