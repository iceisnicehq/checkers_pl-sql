CREATE OR REPLACE VIEW v_game_protocol AS
SELECT
    gm.game_id,
    gm.move_number,
    gm.move_notation,
    gm.is_capture,
    gm.move_timestamp,
    gm.board_position,
    
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN g.player_white_id
        ELSE g.player_black_id
    END AS player_id,
    
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN pw.username
        ELSE pb.username
    END AS username,
    
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN 'W'
        ELSE 'B'
    END AS player_color,
    
    -- Определение превращения: упрощенная версия
    -- Для точного определения нужно декодировать позиции, что неэффективно в view
    -- Можно улучшить, добавив поле is_promotion в game_moves при создании хода
    'N' AS is_promotion, -- Заглушка: требует декодирования позиций для точного определения
    
    -- Отметка окончания игры: если это последний ход перед завершением
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM games g2 
            WHERE g2.game_id = gm.game_id 
            AND g2.status IN ('V', 'D', 'T', 'R')
            AND g2.end_time >= gm.move_timestamp
            AND NOT EXISTS (
                SELECT 1 FROM game_moves gm_next
                WHERE gm_next.game_id = gm.game_id
                AND gm_next.move_number > gm.move_number
            )
        ) THEN 'Y'
        ELSE 'N'
    END AS is_game_ending_move

FROM
    game_moves gm
JOIN
    games g ON gm.game_id = g.game_id
LEFT JOIN
    players pw ON g.player_white_id = pw.player_id
LEFT JOIN
    players pb ON g.player_black_id = pb.player_id;