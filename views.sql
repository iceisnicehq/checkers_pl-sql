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


CREATE OR REPLACE VIEW v_game_protocol AS
SELECT
    gm.game_id,
    gm.move_number,
CASE WHEN MOD(gm.move_number, 2) = 1 THEN (gm.move_number + 1) / 2 ELSE gm.move_number / 2 END AS turn_number,
    p.username,
    gm.move_notation,
    gm.is_capture,
    gm.move_timestamp
FROM
    game_moves gm
JOIN
    players p ON gm.player_id = p.player_id
ORDER BY
    gm.game_id, gm.move_number;
    
COMMENT ON COLUMN v_game_protocol.turn_number IS 'Номер полного хода (1. e2-e4 e7-e5)';

CREATE OR REPLACE VIEW v_player_history AS
SELECT
    g.game_id,
    p_user.username AS player_name,
    p_opponent.username AS opponent_name,
    CASE
        WHEN g.status IN ('WHITE_WIN', 'BLACK_WIN') AND g.winner_player_id = p_user.player_id THEN 'WIN'
        WHEN g.status = 'DRAW' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    g.status AS final_status,
    g.start_time,
    g.end_time,
    (SELECT COUNT(*) FROM game_moves WHERE game_id = g.game_id) AS total_moves
FROM
    games g
JOIN
    players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
LEFT JOIN
    players p_opponent ON (
        (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
        (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
    )
WHERE
    g.status NOT IN ('ACTIVE', 'WAITING', 'SCHEDULED')
    AND p_user.username = USER;


CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_results AS (
    -- Собираем все участия в завершенных играх
    SELECT player_white_id AS player_id, status, winner_player_id FROM games WHERE status NOT IN ('ACTIVE', 'WAITING', 'ABORTED', 'SCHEDULED') AND player_white_id IS NOT NULL
    UNION ALL
    SELECT player_black_id AS player_id, status, winner_player_id FROM games WHERE status NOT IN ('ACTIVE', 'WAITING', 'ABORTED', 'SCHEDULED') AND player_black_id IS NOT NULL
),
player_stats AS (
    SELECT
        player_id,
        COUNT(*) AS games_played,
        SUM(CASE WHEN winner_player_id = player_id THEN 1 ELSE 0 END) AS wins,
        SUM(CASE WHEN status = 'DRAW' THEN 1 ELSE 0 END) AS draws,
        SUM(CASE WHEN status NOT IN ('DRAW') AND (winner_player_id IS NULL OR winner_player_id != player_id) THEN 1 ELSE 0 END) AS losses
    FROM
        game_results
    GROUP BY
        player_id
)
SELECT
    p.username,
    ps.games_played,
    ps.wins,
    ps.losses,
    ps.draws,
    -- Поведение при 0 в знаменателе: если поражений 0, считаем успех 100% от числа побед. Если и побед 0, то 0.
    CASE
        WHEN ps.losses = 0 THEN ps.wins * 100
        ELSE ROUND((ps.wins / ps.losses) * 100, 2)
    END AS success_rate_percent
FROM
    player_stats ps
JOIN
    players p ON ps.player_id = p.player_id
ORDER BY
    success_rate_percent DESC, wins DESC;