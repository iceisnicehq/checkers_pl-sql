-- =============================================================================
-- Файл: views.sql
-- Описание: Представления для отображения информации пользователям.
-- =============================================================================

CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    p_creator.username AS creator_username,
    -- Определяем тип вызова: прямой (если второй игрок указан) или открытый
    CASE
        WHEN g.player_white_id IS NOT NULL AND g.player_black_id IS NOT NULL THEN 'Direct Challenge'
        ELSE 'Open Challenge'
    END AS challenge_type,
    -- Показываем, кому адресован вызов, если он прямой
    CASE
        WHEN g.player_white_id = p_creator.player_id THEN p_opponent.username
        ELSE p_creator_as_opponent.username
    END AS challenged_player,
    g.start_time AS created_at
FROM
    games g
JOIN
    -- Находим создателя (он всегда есть)
    players p_creator ON (g.player_white_id = p_creator.player_id OR g.player_black_id = p_creator.player_id)
LEFT JOIN
    -- Находим оппонента, если он указан
    players p_opponent ON (g.player_black_id = p_opponent.player_id AND g.player_white_id = p_creator.player_id)
LEFT JOIN
    players p_creator_as_opponent ON (g.player_white_id = p_creator_as_opponent.player_id AND g.player_black_id = p_creator.player_id)
WHERE
    g.status = 'WAITING';

COMMENT ON VIEW v_open_games IS 'Показывает все партии, ожидающие второго игрока (игровое лобби).';