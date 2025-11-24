-- View для истории игрока за период с фильтрацией
CREATE OR REPLACE VIEW v_player_history_by_period AS
SELECT
    p_user.username AS player_name,
    g.game_id,
    CASE
        WHEN g.status IN ('V', 'T', 'R') AND (
             (g.player_white_id = p_user.player_id AND g.winner_player_color = 'W') OR
             (g.player_black_id = p_user.player_id AND g.winner_player_color = 'B')
        ) THEN 'WIN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    p_opponent.username AS opponent_name,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    g.start_time,
    g.end_time,
    CASE 
        WHEN g.status = 'T' THEN 'TIMEOUT'
        WHEN g.status = 'R' THEN 'RESIGN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'NORMAL'
    END AS end_reason,
    (g.end_time - g.start_time) * 24 * 60 AS duration_minutes
FROM games g
JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
JOIN game_rules gr ON g.rule_id = gr.rule_id
LEFT JOIN players p_opponent ON (
    (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
    (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
)
WHERE
    g.status IN ('V', 'D', 'T', 'R')
    AND p_user.username = USER
ORDER BY g.end_time DESC;

