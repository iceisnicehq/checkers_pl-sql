-- View для детальной информации о матче (все игры в матче)
CREATE OR REPLACE VIEW v_match_details AS
WITH match_players AS (
    -- Получаем игроков из первой игры матча
    SELECT 
        m.match_id,
        g_first.player_white_id AS player1_id,
        g_first.player_black_id AS player2_id
    FROM matches m
    JOIN games g_first ON (
        g_first.match_id = m.match_id
        AND g_first.game_id = (
            SELECT MIN(game_id) 
            FROM games 
            WHERE match_id = m.match_id
        )
    )
),
match_scores AS (
    -- Подсчитываем победы для каждого матча
    SELECT 
        m.match_id,
        SUM(CASE WHEN g.winner_player_color = 'W' AND g.status = 'V' THEN 1 ELSE 0 END) AS player1_wins,
        SUM(CASE WHEN g.winner_player_color = 'B' AND g.status = 'V' THEN 1 ELSE 0 END) AS player2_wins,
        SUM(CASE WHEN g.status = 'D' THEN 1 ELSE 0 END) AS draws,
        COUNT(*) AS total_games
    FROM matches m
    LEFT JOIN games g ON g.match_id = m.match_id AND g.status IN ('V', 'D', 'T', 'R')
    GROUP BY m.match_id
)
SELECT
    m.match_id,
    m.rule_id,
    gr.rule_name,
    m.games_to_win,
    m.status,
    p1.username AS player1_username,
    p2.username AS player2_username,
    NVL(ms.player1_wins, 0) AS player1_wins,
    NVL(ms.player2_wins, 0) AS player2_wins,
    NVL(ms.draws, 0) AS draws,
    NVL(ms.total_games, 0) AS total_games,
    pw.username AS winner_username,
    g.game_id,
    g.status AS game_status,
    CASE 
        WHEN g.winner_player_color = 'W' THEN p1.username
        WHEN g.winner_player_color = 'B' THEN p2.username
        ELSE NULL
    END AS game_winner_username,
    CASE 
        WHEN g.status = 'V' THEN 'Победа'
        WHEN g.status = 'D' THEN 'Ничья'
        WHEN g.status = 'T' THEN 'Тайм-аут'
        WHEN g.status = 'R' THEN 'Сдача'
        ELSE g.status
    END AS game_end_reason,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS game_total_moves,
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS game_start_time,
    TO_CHAR(g.end_time, 'YYYY-MM-DD HH24:MI:SS') AS game_end_time,
    ROUND((g.end_time - g.start_time) * 24 * 60, 2) AS game_duration_minutes
FROM matches m
JOIN match_players mp ON m.match_id = mp.match_id
LEFT JOIN players p1 ON mp.player1_id = p1.player_id
LEFT JOIN players p2 ON mp.player2_id = p2.player_id
LEFT JOIN players pw ON m.winner_player_id = pw.player_id
LEFT JOIN game_rules gr ON m.rule_id = gr.rule_id
LEFT JOIN match_scores ms ON m.match_id = ms.match_id
LEFT JOIN games g ON g.match_id = m.match_id
ORDER BY m.match_id, g.game_id;

