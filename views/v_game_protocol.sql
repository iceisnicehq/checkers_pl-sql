CREATE OR REPLACE VIEW v_game_protocol AS
SELECT
    gm.game_id,
    gm.move_number,
    gm.move_notation,
    gm.is_capture,
    gm.move_timestamp,
    gm.board_position,
    
    -- Определяем ID и Имя игрока, сделавшего ход
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN g.player_white_id
        ELSE g.player_black_id
    END AS player_id,
    
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN pw.username
        ELSE pb.username
    END AS username,
    
    -- Определяем Цвет игрока, сделавшего ход
    CASE 
        WHEN MOD(gm.move_number, 2) = 1 THEN 'W'
        ELSE 'B'
    END AS player_color

FROM
    game_moves gm
-- Присоединяем ИГРУ, чтобы найти ID игроков
JOIN
    games g ON gm.game_id = g.game_id
-- Присоединяем Имя Белого Игрока (если он не NULL)
LEFT JOIN
    players pw ON g.player_white_id = pw.player_id
-- Присоединяем Имя Черного Игрока (если он не NULL)
LEFT JOIN
    players pb ON g.player_black_id = pb.player_id;

COMMENT ON TABLE v_game_protocol IS 'Протокол ходов (включая ИИ) для удобного просмотра.';