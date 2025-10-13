CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    p_creator.username AS creator_username,
    -- << ИЗМЕНЕНИЕ: Тип вызова теперь определяется напрямую из статуса
    CASE g.status
        WHEN 'OPEN'       THEN 'Open Challenge'
        WHEN 'CHALLENGED' THEN 'Direct Challenge'
    END AS challenge_type,
    -- << ИЗМЕНЕНИЕ: Вызываемый игрок есть только у прямых вызовов
    CASE
        WHEN g.status = 'CHALLENGED' AND g.player_white_id = g.creator_player_id THEN p_black.username
        WHEN g.status = 'CHALLENGED' AND g.player_black_id = g.creator_player_id THEN p_white.username
        ELSE NULL
    END AS challenged_player,
    g.start_time AS created_at
FROM
    games g
JOIN players p_creator ON g.creator_player_id = p_creator.player_id
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE
    g.status IN ('OPEN', 'CHALLENGED'); -- << ИЗМЕНЕНИЕ: Фильтруем по новым статусам

COMMENT ON TABLE v_open_games IS 'Показывает все партии, ожидающие второго игрока (игровое лобби).';

---
-- V_ACTIVE_GAMES - без изменений, логика остается прежней
---
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

---
-- V_GAME_PROTOCOL - без изменений, не зависит от статуса партии
---
CREATE OR REPLACE VIEW v_game_protocol AS
SELECT
    gm.game_id,
    gm.move_number, -- The simple, sequential move number
    p.username,
    gm.move_notation,
    gm.is_capture,
    gm.move_timestamp,
    gm.board_position -- The board state AFTER the move
FROM
    game_moves gm
JOIN
    players p ON gm.player_id = p.player_id
ORDER BY
    gm.game_id, gm.move_number;

COMMENT ON TABLE v_game_protocol IS 'Протокол ходов партии, включая позицию доски после каждого хода.';

---

CREATE OR REPLACE VIEW v_player_history AS
SELECT
    g.game_id,
    p_user.username AS player_name,
    p_opponent.username AS opponent_name,
    CASE
        WHEN g.status IN ('WHITE_WIN', 'BLACK_WIN') AND g.winner_player_id = p_user.player_id THEN 'WIN'
        WHEN g.status = 'DRAW' THEN 'DRAW'
        ELSE 'LOSS' -- Включает поражения по таймауту, сдаче и т.д.
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
    g.status NOT IN ('ACTIVE', 'OPEN', 'CHALLENGED', 'ABORTED') -- << ИЗМЕНЕНИЕ: Убираем незавершенные партии
    AND p_user.username = USER;

COMMENT ON TABLE v_player_history IS 'История завершенных игр для текущего пользователя.';

---

CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_results AS (
    -- Собираем все участия в завершенных играх
    SELECT player_white_id AS player_id, status, winner_player_id FROM games
    WHERE status NOT IN ('ACTIVE', 'OPEN', 'CHALLENGED', 'ABORTED') AND player_white_id IS NOT NULL -- << ИЗМЕНЕНИЕ
    UNION ALL
    SELECT player_black_id AS player_id, status, winner_player_id FROM games
    WHERE status NOT IN ('ACTIVE', 'OPEN', 'CHALLENGED', 'ABORTED') AND player_black_id IS NOT NULL -- << ИЗМЕНЕНИЕ
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
        WHEN ps.losses = 0 AND ps.wins > 0 THEN ps.wins * 100.0
        WHEN ps.losses = 0 AND ps.wins = 0 THEN 0.0
        ELSE ROUND((ps.wins * 1.0 / ps.losses) * 100, 2) -- Умножение на 1.0 для избежания целочисленного деления
    END AS success_rate_percent
FROM
    player_stats ps
JOIN
    players p ON ps.player_id = p.player_id
ORDER BY
    success_rate_percent DESC, wins DESC;

COMMENT ON TABLE v_leaderboard IS 'Таблица лидеров на основе статистики побед, поражений и ничьих.';

-- 1. Представление для истории игр конкретного пользователя
CREATE OR REPLACE VIEW v_player_history AS
SELECT
    p_user.username AS player_name,
    g.game_id,
    CASE
        WHEN g.winner_player_id = p_user.player_id THEN 'WIN'
        WHEN g.status = 'DRAW' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    p_opponent.username AS opponent_name,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    g.end_time
FROM
    games g
JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
JOIN game_rules gr ON g.rule_id = gr.rule_id
-- Находим оппонента
LEFT JOIN players p_opponent ON (
    (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
    (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
)
WHERE
    -- Показываем только завершенные партии
    g.status IN ('WHITE_WIN', 'BLACK_WIN', 'DRAW', 'TIMEOUT')
    -- Фильтруем для текущего пользователя, который просматривает отчет
    AND p_user.username = USER;

COMMENT ON TABLE v_player_history IS 'История завершенных игр для текущего пользователя.';


-- 2. Представление для таблицы лидеров (рейтинг)
CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_participations AS (
    -- Собираем все участия в завершенных играх в один список
    SELECT player_white_id AS player_id, status, winner_player_id FROM games WHERE status IN ('WHITE_WIN', 'BLACK_WIN', 'DRAW', 'TIMEOUT')
    UNION ALL
    SELECT player_black_id AS player_id, status, winner_player_id FROM games WHERE status IN ('WHITE_WIN', 'BLACK_WIN', 'DRAW', 'TIMEOUT')
),
player_stats AS (
    -- Считаем статистику для каждого игрока
    SELECT
        player_id,
        COUNT(*) AS games_played,
        SUM(CASE WHEN winner_player_id = player_id THEN 1 ELSE 0 END) AS wins,
        SUM(CASE WHEN status = 'DRAW' THEN 1 ELSE 0 END) AS draws,
        SUM(CASE WHEN status NOT IN ('DRAW') AND winner_player_id != player_id THEN 1 ELSE 0 END) AS losses
    FROM game_participations
    WHERE player_id IS NOT NULL
    GROUP BY player_id
)
SELECT
    p.username,
    ps.games_played,
    ps.wins,
    ps.losses,
    ps.draws,
    -- Расчет "успешности": победы / поражения. Обрабатываем деление на ноль.
    CASE
        WHEN ps.losses = 0 AND ps.wins > 0 THEN (ps.wins * 100.0) -- Если нет поражений, но есть победы - максимальный успех
        WHEN ps.losses = 0 AND ps.wins = 0 THEN 0.0 -- Если нет ни побед, ни поражений
        ELSE ROUND((ps.wins * 1.0 / ps.losses) * 100, 2)
    END AS success_rate_percent
FROM
    player_stats ps
JOIN
    players p ON ps.player_id = p.player_id
ORDER BY
    success_rate_percent DESC, wins DESC;

COMMENT ON TABLE v_leaderboard IS 'Таблица лидеров, отсортированная по проценту успеха и количеству побед.';
