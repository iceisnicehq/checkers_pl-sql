-- View для истории игрока: все партии всех игроков с фильтрами
CREATE OR REPLACE VIEW v_player_history AS
SELECT
    g.game_id,
    p_user.username AS player_name,
    CASE
        WHEN g.status IN ('V', 'T', 'R') AND (
             (g.player_white_id = p_user.player_id AND g.winner_player_color = 'W') OR
             (g.player_black_id = p_user.player_id AND g.winner_player_color = 'B')
        ) THEN 'WIN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    p_opponent.username AS opponent_name,
    g.rule_id,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(g.end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
    CASE 
        WHEN g.status = 'T' THEN 'TIMEOUT'
        WHEN g.status = 'R' THEN 'RESIGN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'NORMAL'
    END AS end_reason,
    ROUND((g.end_time - g.start_time) * 24 * 60, 2) AS duration_minutes
FROM games g
JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
JOIN game_rules gr ON g.rule_id = gr.rule_id
LEFT JOIN players p_opponent ON (
    (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
    (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
)
WHERE g.status IN ('V', 'D', 'T', 'R')
ORDER BY g.rule_id, p_user.username, g.end_time DESC;
