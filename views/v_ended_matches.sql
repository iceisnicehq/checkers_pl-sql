CREATE OR REPLACE VIEW v_ended_matches AS
WITH match_players AS (
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
    WHERE m.status = 'C'
),
match_scores AS (
    SELECT 
        m.match_id,
        SUM(CASE WHEN g.winner_player_color = 'W' AND g.status = 'V' THEN 1 ELSE 0 END) AS player1_wins,
        SUM(CASE WHEN g.winner_player_color = 'B' AND g.status = 'V' THEN 1 ELSE 0 END) AS player2_wins,
        SUM(CASE WHEN g.status = 'D' THEN 1 ELSE 0 END) AS draws,
        COUNT(*) AS total_games,
        MIN(g.start_time) AS start_time,
        MAX(g.end_time) AS end_time
    FROM matches m
    LEFT JOIN games g ON g.match_id = m.match_id AND g.status IN ('V', 'D', 'T', 'R')
    WHERE m.status = 'C'
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
    TO_CHAR(ms.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(ms.end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
    ROUND((ms.end_time - ms.start_time) * 24 * 60, 2) AS duration_minutes
FROM matches m
JOIN match_players mp ON m.match_id = mp.match_id
LEFT JOIN players p1 ON mp.player1_id = p1.player_id
LEFT JOIN players p2 ON mp.player2_id = p2.player_id
LEFT JOIN players pw ON m.winner_player_id = pw.player_id
LEFT JOIN game_rules gr ON m.rule_id = gr.rule_id
LEFT JOIN match_scores ms ON m.match_id = ms.match_id
WHERE m.status = 'C'
ORDER BY ms.end_time DESC;

