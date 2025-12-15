BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'DAILY_CHECKERS_PUZZLE_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
        DECLARE
            v_puzzle_id puzzles.puzzle_id%TYPE;
            v_today     DATE := TRUNC(SYSDATE);
            v_count     PLS_INTEGER;
        BEGIN
            SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;

            IF v_count = 0 THEN
                BEGIN
                    SELECT puzzle_id INTO v_puzzle_id
                    FROM (
                        SELECT p.puzzle_id
                        FROM puzzles p
                        LEFT JOIN daily_puzzles dp ON p.puzzle_id = dp.puzzle_id AND dp.puzzle_date >= (v_today - 30)
                        WHERE p.created_by_player_id IS NULL 
                        AND dp.puzzle_id IS NULL 
                        ORDER BY DBMS_RANDOM.VALUE
                    ) WHERE ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        SELECT puzzle_id INTO v_puzzle_id
                        FROM (
                            SELECT puzzle_id FROM puzzles 
                            WHERE created_by_player_id IS NULL
                            ORDER BY DBMS_RANDOM.VALUE
                        ) WHERE ROWNUM = 1;
                END;

                INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_puzzle_id);
                COMMIT;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    ]',
    start_date      => TRUNC(SYSTIMESTAMP) + INTERVAL '1' DAY + INTERVAL '1' HOUR,
    repeat_interval => 'FREQ=DAILY; BYHOUR=1; BYMINUTE=0; BYSECOND=0',    
    enabled         => TRUE,
    comments        => 'Выбирает случайную задачу для ежедневной задачи.'
  );
  
  DBMS_OUTPUT.PUT_LINE('Job DAILY_CHECKERS_PUZZLE_JOB успешно создан.');
END;
