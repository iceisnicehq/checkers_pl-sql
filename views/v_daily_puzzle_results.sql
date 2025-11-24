-- View для результатов daily puzzles
CREATE OR REPLACE VIEW v_daily_puzzle_results AS
SELECT
    dp.daily_puzzle_id,
    dp.puzzle_date,
    p.puzzle_id,
    p.difficulty_level,
    p.moves_to_solve,
    p.turn_to_move,
    p.end_condition,
    -- Статистика решений
    COUNT(DISTINCT g.game_id) AS total_attempts,
    SUM(CASE WHEN g.puzzle_status = 's' THEN 1 ELSE 0 END) AS successful_solves,
    SUM(CASE WHEN g.puzzle_status = 'f' THEN 1 ELSE 0 END) AS failed_attempts,
    SUM(CASE WHEN g.puzzle_status = 'p' OR g.puzzle_status IS NULL THEN 1 ELSE 0 END) AS in_progress,
    -- Среднее время решения (для успешных)
    ROUND(AVG(CASE 
        WHEN g.puzzle_status = 's' AND g.end_time IS NOT NULL AND g.start_time IS NOT NULL
        THEN (EXTRACT(DAY FROM (g.end_time - g.start_time)) * 24 * 60 + 
              EXTRACT(HOUR FROM (g.end_time - g.start_time)) * 60 +
              EXTRACT(MINUTE FROM (g.end_time - g.start_time)))
        ELSE NULL
    END), 2) AS avg_solve_time_minutes,
    -- Среднее количество ходов для решения
    ROUND(AVG(CASE 
        WHEN g.puzzle_status = 's'
        THEN (SELECT COUNT(*) FROM game_moves gm WHERE gm.game_id = g.game_id)
        ELSE NULL
    END), 2) AS avg_moves_to_solve
FROM daily_puzzles dp
JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
LEFT JOIN games g ON g.puzzle_id = p.puzzle_id AND g.is_daily_puzzle = 'Y'
GROUP BY
    dp.daily_puzzle_id,
    dp.puzzle_date,
    p.puzzle_id,
    p.difficulty_level,
    p.moves_to_solve,
    p.turn_to_move,
    p.end_condition
ORDER BY dp.puzzle_date DESC;

COMMENT ON VIEW v_daily_puzzle_results IS 'Результаты daily puzzles: статистика попыток, успешных решений, среднее время и количество ходов.';

