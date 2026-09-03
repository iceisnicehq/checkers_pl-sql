CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    g.match_id,
    
    -- Определяем имя создателя на основе его цвета
    CASE g.creator_player_color
        WHEN 'W' THEN p_white.username
        WHEN 'B' THEN p_black.username
    END AS creator_username,
    
    CASE g.status
        WHEN 'O' THEN 'Open Challenge'
        WHEN 'C' THEN 'Direct Challenge'
    END AS challenge_type,
    
    -- Определяем имя того, кого вызвали (если это прямой вызов 'C')
    CASE 
        WHEN g.status = 'C' THEN
            CASE g.creator_player_color
                WHEN 'W' THEN p_black.username -- Создатель Белый -> Вызван Черный
                WHEN 'B' THEN p_white.username -- Создатель Черный -> Вызван Белый
            END
        ELSE NULL
    END AS challenged_player,
    
    -- Определяем цвет, который получит присоединяющийся игрок
    CASE 
        WHEN g.status = 'O' THEN
            -- Для открытой игры: присоединяющийся получает противоположный цвет создателю
            CASE g.creator_player_color
                WHEN 'W' THEN 'B' -- Создатель белые -> присоединяющийся черные
                WHEN 'B' THEN 'W' -- Создатель черные -> присоединяющийся белые
            END
        WHEN g.status = 'C' THEN
            -- Для прямого вызова: присоединяющийся получает противоположный цвет создателю
            CASE g.creator_player_color
                WHEN 'W' THEN 'B' -- Создатель белые -> вызванный черные
                WHEN 'B' THEN 'W' -- Создатель черные -> вызванный белые
            END
    END AS your_color,
    
    TO_CHAR(g.start_time, 'YYYY-MM-DD HH24:MI:SS') AS created_at
    
FROM games g
-- Нам больше не нужен JOIN p_creator, так как нет creator_player_id
-- Достаточно джойнов по белым и черным
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE g.status IN ('O', 'C');