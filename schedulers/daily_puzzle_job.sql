BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  -- Создаем джоб заново
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'DAILY_CHECKERS_PUZZLE_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
        DECLARE
            v_puzzle_id puzzles.puzzle_id%TYPE;
            v_today     DATE := TRUNC(SYSDATE);
            v_count     PLS_INTEGER;
        BEGIN
            -- Проверка на существование
            SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;

            IF v_count = 0 THEN
                BEGIN
                    -- 1. Попытка найти уникальный за 30 дней
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
                        -- 2. Fallback: Любой серверный пазл
                        SELECT puzzle_id INTO v_puzzle_id
                        FROM (
                            SELECT puzzle_id FROM puzzles 
                            WHERE created_by_player_id IS NULL
                            ORDER BY DBMS_RANDOM.VALUE
                        ) WHERE ROWNUM = 1;
                END;

                -- Вставка
                INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_puzzle_id);
                COMMIT;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- В реальном проде здесь стоит писать в лог ошибок
                NULL;
        END;
    ]',
    start_date      => TRUNC(SYSTIMESTAMP) + INTERVAL '1' DAY + INTERVAL '1' HOUR, -- Завтра в 01:00
    repeat_interval => 'FREQ=DAILY; BYHOUR=1; BYMINUTE=0; BYSECOND=0',             -- Ежедневно в 01:00
    enabled         => TRUE,
    comments        => 'Selects a random checkers puzzle for the daily challenge.'
  );
  
  DBMS_OUTPUT.PUT_LINE('Job DAILY_CHECKERS_PUZZLE_JOB успешно создан.');
END;
