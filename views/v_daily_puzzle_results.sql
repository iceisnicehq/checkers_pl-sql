CREATE OR REPLACE VIEW v_daily_puzzle_results AS
SELECT
    g.game_id,
    dp.puzzle_date,
    pz.puzzle_id,
    COALESCE(pw.username, pb.username) AS player_name,
    CASE 
        WHEN g.puzzle_status = 's' THEN 'Решено'
        WHEN g.puzzle_status = 'f' THEN 'Не решено'
        WHEN g.puzzle_status = 'p' OR g.puzzle_status IS NULL THEN 'В процессе'
        ELSE 'Неизвестно'
    END AS result
FROM games g
JOIN puzzles pz ON g.puzzle_id = pz.puzzle_id
JOIN daily_puzzles dp ON (
    dp.puzzle_id = g.puzzle_id 
    AND TRUNC(g.start_time) = dp.puzzle_date
)
LEFT JOIN players pw ON g.player_white_id = pw.player_id
LEFT JOIN players pb ON g.player_black_id = pb.player_id
WHERE g.is_daily_puzzle = 'Y'
  AND g.puzzle_status IS NOT NULL
ORDER BY dp.puzzle_date DESC, 
    CASE 
        WHEN g.puzzle_status = 's' THEN 1
        WHEN g.puzzle_status = 'f' THEN 2
        WHEN g.puzzle_status = 'p' THEN 3
        ELSE 4
    END;
