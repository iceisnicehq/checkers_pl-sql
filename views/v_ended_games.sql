-- View для завершенных игр
CREATE OR REPLACE VIEW v_ended_games AS
SELECT
    g.game_id,
    g.match_id,
    pw.username AS white_player_username,
    pb.username AS black_player_username,
    g.rule_id,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    CASE 
        WHEN g.winner_player_color = 'W' THEN pw.username
        WHEN g.winner_player_color = 'B' THEN pb.username
        ELSE NULL
    END AS winner_username,
    CASE 
        WHEN g.status = 'V' THEN 'Победа'
        WHEN g.status = 'D' THEN 'Ничья'
        WHEN g.status = 'T' THEN 'Тайм-аут'
        WHEN g.status = 'R' THEN 'Сдача'
        ELSE g.status
    END AS end_reason,
    ROUND((g.end_time - g.start_time) * 24 * 60, 2) AS duration_minutes,
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(g.end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time
FROM games g
LEFT JOIN players pw ON g.player_white_id = pw.player_id
LEFT JOIN players pb ON g.player_black_id = pb.player_id
LEFT JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE g.status IN ('V', 'D', 'T', 'R')
ORDER BY g.end_time DESC;

