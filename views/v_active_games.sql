CREATE OR REPLACE VIEW v_active_games AS
SELECT
    g.game_id,
    p_white.username AS white_player,
    p_black.username AS black_player,
    gr.rule_name
FROM games g
JOIN players p_white ON g.player_white_id = p_white.player_id
JOIN players p_black ON g.player_black_id = p_black.player_id
JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE g.status = 'A';