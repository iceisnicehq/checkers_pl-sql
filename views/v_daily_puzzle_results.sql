-- View для результатов daily puzzles: только для тех, кто решал
CREATE OR REPLACE VIEW v_daily_puzzle_results AS
SELECT
    g.game_id,
    dp.puzzle_date,
    pz.puzzle_id,
    p.username AS player_name,
    CASE 
        WHEN g.puzzle_status = 's' THEN 'Решено'
        WHEN g.puzzle_status = 'f' THEN 'Не решено'
        WHEN g.puzzle_status = 'p' OR g.puzzle_status IS NULL THEN 'В процессе'
        ELSE 'Неизвестно'
    END AS result
FROM daily_puzzles dp
JOIN puzzles pz ON dp.puzzle_id = pz.puzzle_id
JOIN games g ON g.puzzle_id = pz.puzzle_id AND g.is_daily_puzzle = 'Y'
JOIN players p ON (g.player_white_id = p.player_id OR g.player_black_id = p.player_id)
WHERE g.puzzle_status IS NOT NULL
ORDER BY dp.puzzle_date DESC, 
    CASE 
        WHEN g.puzzle_status = 's' THEN 1
        WHEN g.puzzle_status = 'f' THEN 2
        WHEN g.puzzle_status = 'p' THEN 3
        ELSE 4
    END;
