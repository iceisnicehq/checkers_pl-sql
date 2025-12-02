CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    g.match_id,
    CASE g.creator_player_color
        WHEN 'W' THEN p_white.username
        WHEN 'B' THEN p_black.username
    END AS creator_username,
    
    CASE g.status
        WHEN 'O' THEN 'Open Challenge'
        WHEN 'C' THEN 'Direct Challenge'
    END AS challenge_type,
    CASE 
        WHEN g.status = 'C' THEN
            CASE g.creator_player_color
                WHEN 'W' THEN p_black.username
                WHEN 'B' THEN p_white.username
            END
        ELSE NULL
    END AS challenged_player,
    CASE 
        WHEN g.status = 'O' THEN

            CASE g.creator_player_color
                WHEN 'W' THEN 'B'
                WHEN 'B' THEN 'W'
            END
        WHEN g.status = 'C' THEN

            CASE g.creator_player_color
                WHEN 'W' THEN 'B'
                WHEN 'B' THEN 'W'
            END
    END AS your_color,
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS created_at
FROM games g
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE g.status IN ('O', 'C');