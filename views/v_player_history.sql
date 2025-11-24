CREATE OR REPLACE VIEW v_player_history AS
SELECT
    p_user.username AS player_name,
    g.game_id,
    CASE
        WHEN g.status = 'V' AND g.winner_player_id = p_user.player_id THEN 'WIN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    p_opponent.username AS opponent_name,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    g.end_time
FROM games g
JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
JOIN game_rules gr ON g.rule_id = gr.rule_id
LEFT JOIN players p_opponent ON (
    (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
    (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
)
WHERE
    g.status IN ('V', 'D', 'T')
    AND p_user.username = USER;