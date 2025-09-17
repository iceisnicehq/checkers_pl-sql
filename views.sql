-- =============================================================================
-- Файл: views.sql
-- Описание: Представления для отображения информации пользователям.
-- =============================================================================

CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    p_creator.username AS creator_username,
    -- Тип вызова определяется просто: если оба слота заняты, это прямой вызов
    CASE
        WHEN g.player_white_id IS NOT NULL AND g.player_black_id IS NOT NULL
        THEN 'Direct Challenge'
        ELSE 'Open Challenge'
    END AS challenge_type,
    -- Вызываемый игрок - это тот, кто не является создателем
    CASE
        WHEN g.player_white_id = g.creator_player_id THEN p_black.username
        ELSE p_white.username
    END AS challenged_player,
    g.start_time AS created_at
FROM
    games g
JOIN players p_creator ON g.creator_player_id = p_creator.player_id
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE
    g.status = 'WAITING';

COMMENT ON TABLE v_open_games IS 'Показывает все партии, ожидающие второго игрока (игровое лобби).';

CREATE OR REPLACE VIEW v_active_games AS
SELECT
    g.game_id,
    p_white.username AS white_player,
    p_black.username AS black_player,
    g.last_move_at,
    gr.rule_name
FROM
    games g
JOIN players p_white ON g.player_white_id = p_white.player_id
JOIN players p_black ON g.player_black_id = p_black.player_id
JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE
    g.status = 'ACTIVE';

COMMENT ON TABLE v_active_games IS 'Показывает все активные на данный момент партии для наблюдения.';