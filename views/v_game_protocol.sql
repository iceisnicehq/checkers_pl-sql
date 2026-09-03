-- View для протокола партии: все ходы со всеми полями статуса
CREATE OR REPLACE VIEW v_game_protocol AS
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
    gm.move_number,
    gm.move_notation,
    gm.is_capture,
    TO_CHAR(gm.move_timestamp, 'YYYY-MM-DD HH24:MI:SS') AS move_timestamp,
    gm.board_position,
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN pw.username
        ELSE pb.username
    END AS move_player_username,
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN 'W'
        ELSE 'B'
    END AS move_player_color,
    -- Текущая позиция доски (из последнего хода или начальная)
    COALESCE(
        (SELECT board_position FROM game_moves gm2
         WHERE gm2.game_id = g.game_id 
         ORDER BY gm2.move_number DESC 
         FETCH FIRST 1 ROW ONLY),
        (SELECT game_logic.get_initial_position(g.rule_id) FROM DUAL)
    ) AS current_board_position,
    -- Количество ходов
    (SELECT COUNT(*) FROM game_moves gm3 WHERE gm3.game_id = g.game_id) AS move_count,
    -- Последний результат валидации (из audit_log)
    (SELECT event_msg FROM audit_log 
     WHERE game_id = g.game_id 
     AND (event_msg LIKE '%Неверный ход%' OR event_msg LIKE '%неверный ход%' OR 
          event_msg LIKE '%Нелегальный ход%' OR event_msg LIKE '%нелегальный ход%')
     ORDER BY log_timestamp DESC 
     FETCH FIRST 1 ROW ONLY) AS last_validation_result
FROM games g
LEFT JOIN players pw ON g.player_white_id = pw.player_id
LEFT JOIN players pb ON g.player_black_id = pb.player_id
LEFT JOIN game_rules gr ON g.rule_id = gr.rule_id
LEFT JOIN game_moves gm ON g.game_id = gm.game_id
ORDER BY g.game_id, gm.move_number;
