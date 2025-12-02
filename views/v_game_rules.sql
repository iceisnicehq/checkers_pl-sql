-- View для правил игры
CREATE OR REPLACE VIEW v_game_rules AS
SELECT
    rule_id,
    rule_name,
    board_size,
    rule_description
FROM game_rules
ORDER BY rule_id;

