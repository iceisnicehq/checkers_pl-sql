-- View для статуса партии: идентификаторы участников, вариант правил, очередь, таймеры, текст позиции
CREATE OR REPLACE VIEW v_game_status AS
SELECT
    g.game_id,
    g.player_white_id,
    pw.username AS white_player_username,
    g.player_black_id,
    pb.username AS black_player_username,
    g.rule_id,
    gr.rule_name,
    g.current_turn,
    g.status,
    g.time_limit_move_sec,
    g.time_limit_game_sec,
    g.start_time,
    g.end_time,
    -- Текущая позиция доски (из последнего хода или начальная)
    COALESCE(
        (SELECT board_position FROM game_moves 
         WHERE game_id = g.game_id 
         ORDER BY move_number DESC 
         FETCH FIRST 1 ROW ONLY),
        (SELECT game_logic.get_initial_position(g.rule_id) FROM DUAL)
    ) AS current_board_position,
    -- Количество ходов
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS move_count,
    -- Последний результат валидации (из audit_log)
    (SELECT event_msg FROM audit_log 
     WHERE game_id = g.game_id 
     AND (event_msg LIKE '%VALIDATION%' OR event_msg LIKE '%ERROR%' OR event_msg LIKE '%INVALID%')
     ORDER BY log_timestamp DESC 
     FETCH FIRST 1 ROW ONLY) AS last_validation_result
FROM games g
LEFT JOIN players pw ON g.player_white_id = pw.player_id
LEFT JOIN players pb ON g.player_black_id = pb.player_id
LEFT JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE g.status IN ('A', 'O', 'C', 'V', 'D', 'T', 'R');

