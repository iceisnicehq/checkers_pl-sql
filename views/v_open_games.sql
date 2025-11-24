CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    p_creator.username AS creator_username,
    CASE g.status
        WHEN 'O' THEN 'Open Challenge'
        WHEN 'C' THEN 'Direct Challenge'
    END AS challenge_type,
    CASE
        WHEN g.status = 'C' AND g.player_white_id = g.creator_player_id THEN p_black.username
        WHEN g.status = 'C' AND g.player_black_id = g.creator_player_id THEN p_white.username
        ELSE NULL
    END AS challenged_player,
    g.start_time AS created_at
FROM games g
JOIN players p_creator ON g.creator_player_id = p_creator.player_id
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE g.status IN ('O', 'C');