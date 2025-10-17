--- V_OPEN_GAMES
CREATE OR REPLACE VIEW v_open_games AS
SELECT
    g.game_id,
    p_creator.username AS creator_username,
    CASE g.status
        WHEN 'O' THEN 'Open Challenge'
        WHEN 'C' THEN 'Direct Challenge'
    END AS challenge_type,
    CASE
        WHEN g.status = 'C' AND g.player_white_id = g.creator_player_id THEN p_black.username
        WHEN g.status = 'C' AND g.player_black_id = g.creator_player_id THEN p_white.username
        ELSE NULL
    END AS challenged_player,
    g.start_time AS created_at
FROM games g
JOIN players p_creator ON g.creator_player_id = p_creator.player_id
LEFT JOIN players p_white ON g.player_white_id = p_white.player_id
LEFT JOIN players p_black ON g.player_black_id = p_black.player_id
WHERE g.status IN ('O', 'C');

---
-- V_GAME_PROTOCOL - без изменений, не зависит от статуса партии
---
CREATE OR REPLACE VIEW v_game_protocol AS
SELECT
    gm.game_id,
    gm.move_number,
    p.username,
    gm.move_notation,
    gm.is_capture,
    gm.move_timestamp,
    gm.board_position
FROM
    game_moves gm
JOIN
    players p ON gm.player_id = p.player_id;

COMMENT ON TABLE v_game_protocol IS 'Протокол ходов с именами игроков для удобного просмотра.';

--- V_ACTIVE_GAMES
CREATE OR REPLACE VIEW v_active_games AS
SELECT
    g.game_id,
    p_white.username AS white_player,
    p_black.username AS black_player,
    g.last_move_at,
    gr.rule_name
FROM games g
JOIN players p_white ON g.player_white_id = p_white.player_id
JOIN players p_black ON g.player_black_id = p_black.player_id
JOIN game_rules gr ON g.rule_id = gr.rule_id
WHERE g.status = 'A';

--- V_PLAYER_HISTORY
CREATE OR REPLACE VIEW v_player_history AS
SELECT
    p_user.username AS player_name,
    g.game_id,
    CASE
        WHEN g.status = 'V' AND g.winner_player_id = p_user.player_id THEN 'WIN'
        WHEN g.status = 'D' THEN 'DRAW'
        ELSE 'LOSS'
    END AS result,
    p_opponent.username AS opponent_name,
    gr.rule_name,
    (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id) AS total_moves,
    g.end_time
FROM games g
JOIN players p_user ON (g.player_white_id = p_user.player_id OR g.player_black_id = p_user.player_id)
JOIN game_rules gr ON g.rule_id = gr.rule_id
LEFT JOIN players p_opponent ON (
    (g.player_white_id = p_user.player_id AND g.player_black_id = p_opponent.player_id) OR
    (g.player_black_id = p_user.player_id AND g.player_white_id = p_opponent.player_id)
)
WHERE
    g.status IN ('V', 'D', 'T')
    AND p_user.username = USER;

--- V_LEADERBOARD
CREATE OR REPLACE VIEW v_leaderboard AS
WITH game_participations AS (
    SELECT player_white_id AS player_id, status, winner_player_id FROM games WHERE status IN ('V', 'D', 'T')
    UNION ALL
    SELECT player_black_id AS player_id, status, winner_player_id FROM games WHERE status IN ('V', 'D', 'T')
),
player_stats AS (
    SELECT
        player_id,
        COUNT(*) AS games_played,
        SUM(CASE WHEN winner_player_id = player_id THEN 1 ELSE 0 END) AS wins,
        SUM(CASE WHEN status = 'D' THEN 1 ELSE 0 END) AS draws,
        SUM(CASE WHEN status != 'D' AND (winner_player_id IS NULL OR winner_player_id != player_id) THEN 1 ELSE 0 END) AS losses
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
    CASE
        WHEN ps.losses = 0 AND ps.wins > 0 THEN (ps.wins * 100.0)
        WHEN ps.losses = 0 AND ps.wins = 0 THEN 0.0
        ELSE ROUND((ps.wins * 1.0 / ps.losses) * 100, 2)
    END AS success_rate_percent
FROM
    player_stats ps
JOIN
    players p ON ps.player_id = p.player_id
ORDER BY
    success_rate_percent DESC, wins DESC;