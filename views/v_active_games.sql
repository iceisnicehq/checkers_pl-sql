CREATE OR REPLACE VIEW v_active_games AS
SELECT
    g.game_id,
    g.match_id,
    pw.username AS white_player_username,
    pb.username AS black_player_username,
    g.rule_id,
    gr.rule_name,
    g.current_turn,
    g.status,
    g.time_limit_move_sec,
    g.time_limit_game_sec,
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(g.end_time, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
    COALESCE(
        (SELECT board_position FROM game_moves 
         WHERE game_id = g.game_id 
         ORDER BY move_number DESC 
         FETCH FIRST 1 ROW ONLY),
        CASE 
            WHEN gr.board_size = 8 THEN 
                '1b1b1b1bb1b1b1b2b1b1b1b16w1w1w1w2w1w1w1ww1w1w1w1'
            ELSE 
                '1b1b1b1b1bb1b1b1b1b2b1b1b1b1bb1b1b1b1b22w1w1w1w1ww1w1w1w1w2w1w1w1w1ww1w1w1w1w1'
        END
    ) AS current_board_position,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS move_count,
    (SELECT event_msg FROM audit_log 
     WHERE game_id = g.game_id 
     AND (event_msg LIKE '%ход%' OR event_msg LIKE '%ХОД%' OR event_msg LIKE '%неверный ход%' OR event_msg LIKE '%нелегальный ход%')
     ORDER BY log_timestamp DESC 
     FETCH FIRST 1 ROW ONLY) AS last_validation_result
FROM games g
LEFT JOIN players pw ON g.player_white_id = pw.player_id
LEFT JOIN players pb ON g.player_black_id = pb.player_id
LEFT JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE g.status IN ('A', 'O', 'C');
