CREATE OR REPLACE VIEW v_open_matches AS
WITH match_players AS (
    SELECT 
        m.match_id,
        g_first.player_white_id AS player1_id,
        g_first.player_black_id AS player2_id,
        g_first.creator_player_color,
        g_first.game_id
    FROM matches m
    JOIN games g_first ON (
        g_first.match_id = m.match_id
        AND g_first.game_id = (
            SELECT MIN(game_id) 
            FROM games 
            WHERE match_id = m.match_id
        )
    )
    WHERE m.status = 'O'
)
SELECT
    m.match_id,
    m.rule_id,
    gr.rule_name,
    m.games_to_win,
    m.status,
    CASE mp.creator_player_color
        WHEN 'W' THEN p1.username
        WHEN 'B' THEN p2.username
    END AS creator_username,
    CASE 
        WHEN mp.creator_player_color = 'W' THEN p2.username
        WHEN mp.creator_player_color = 'B' THEN p1.username
        ELSE NULL
    END AS challenged_player,
    p1.username AS player1_username,
    p2.username AS player2_username,
    mp.game_id AS waiting_game_id,
    TO_CHAR(g_first.start_time, 'YYYY-MM-DD HH24:MI:SS') AS created_at
FROM matches m
JOIN match_players mp ON m.match_id = mp.match_id
LEFT JOIN players p1 ON mp.player1_id = p1.player_id
LEFT JOIN players p2 ON mp.player2_id = p2.player_id
LEFT JOIN game_rules gr ON m.rule_id = gr.rule_id
LEFT JOIN games g_first ON mp.game_id = g_first.game_id
WHERE m.status = 'O'
ORDER BY m.match_id;

