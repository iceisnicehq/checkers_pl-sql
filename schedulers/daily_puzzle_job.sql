-----DAILY PUZZLE JOB SETUP-----
-- Запускаем этот блок один раз, чтобы создать ежедневную задачу на СЕГОДНЯ (если ее нет)
DECLARE
    v_puzzle_id puzzles.puzzle_id%TYPE;
    v_today     DATE := TRUNC(SYSDATE);
    v_count     PLS_INTEGER;
BEGIN
    -- Check if a puzzle for today already exists
    SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;

    IF v_count = 0 THEN
        -- Select a random server-created puzzle that wasn't used recently (e.g., last 30 days)
        SELECT puzzle_id INTO v_puzzle_id
        FROM (
            SELECT p.puzzle_id
            FROM puzzles p
            LEFT JOIN daily_puzzles dp ON p.puzzle_id = dp.puzzle_id AND dp.puzzle_date >= (v_today - 30) -- Не было за последние 30 дней
            WHERE p.created_by_player_id IS NULL -- Only server puzzles
            AND dp.puzzle_id IS NULL -- Not used recently
            ORDER BY DBMS_RANDOM.VALUE
        ) WHERE ROWNUM = 1;

        -- Assign it for today
        INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_puzzle_id);
        COMMIT;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Handle case where no suitable puzzle is found (e.g., log an error)
        NULL; -- Or raise an error, or pick any puzzle
END;
/

-- Создаем JOB, который будет запускаться КАЖДУЮ НОЧЬ
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'DAILY_CHECKERS_PUZZLE_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
        DECLARE
            v_puzzle_id puzzles.puzzle_id%TYPE;
            v_today     DATE := TRUNC(SYSDATE);
            v_count     PLS_INTEGER;
        BEGIN
            -- Check if a puzzle for today already exists
            SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;

            IF v_count = 0 THEN
                -- Select a random server-created puzzle that wasn't used recently (e.g., last 30 days)
                SELECT puzzle_id INTO v_puzzle_id
                FROM (
                    SELECT p.puzzle_id
                    FROM puzzles p
                    LEFT JOIN daily_puzzles dp ON p.puzzle_id = dp.puzzle_id AND dp.puzzle_date >= (v_today - 30)
                    WHERE p.created_by_player_id IS NULL -- Only server puzzles
                    AND dp.puzzle_id IS NULL -- Not used recently
                    ORDER BY DBMS_RANDOM.VALUE
                ) WHERE ROWNUM = 1;

                -- Assign it for today
                INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_puzzle_id);
                COMMIT;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Handle case where no suitable puzzle is found (e.g., log an error)
                NULL; -- Or raise an error, or pick any puzzle
        END;
    ]',
    start_date      => TRUNC(SYSTIMESTAMP) + INTERVAL '1' DAY + INTERVAL '1' HOUR, -- Start tomorrow at 1 AM
    repeat_interval => 'FREQ=DAILY; BYHOUR=1; BYMINUTE=0; BYSECOND=0', -- Run daily at 1 AM
    enabled         => TRUE,
    comments        => 'Selects a random checkers puzzle for the daily challenge.');
END;
/