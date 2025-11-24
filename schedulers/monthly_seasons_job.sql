-- Scheduler job для автоматического создания новых сезонов каждый месяц
-- Создает сезон с названием "Месяц-Год" (например, "Ноябрь-2025")

BEGIN
  -- Удаляем старый джоб если существует
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'MONTHLY_SEASONS_JOB');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  -- Создаем джоб
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'MONTHLY_SEASONS_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
        DECLARE
            v_current_month DATE := TRUNC(SYSDATE, 'MM');
            v_next_month DATE := ADD_MONTHS(v_current_month, 1);
            v_season_name VARCHAR2(100);
            v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
            );
            v_month_num PLS_INTEGER;
            v_year_num PLS_INTEGER;
            v_count PLS_INTEGER;
        BEGIN
            -- Проверяем, существует ли уже сезон на текущий месяц
            SELECT COUNT(*) INTO v_count
            FROM seasons
            WHERE start_date <= v_current_month
              AND end_date >= v_current_month;
            
            IF v_count = 0 THEN
                -- Создаем новый сезон
                v_month_num := EXTRACT(MONTH FROM v_current_month);
                v_year_num := EXTRACT(YEAR FROM v_current_month);
                v_season_name := v_month_names(v_month_num) || '-' || v_year_num;
                
                INSERT INTO seasons (season_name, start_date, end_date)
                VALUES (v_season_name, v_current_month, v_next_month - 1);
                
                COMMIT;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- Логируем ошибку но не падаем
                NULL;
        END;
    ]',
    start_date      => TRUNC(SYSTIMESTAMP, 'MM') + INTERVAL '1' MONTH + INTERVAL '1' DAY + INTERVAL '1' HOUR, -- 1-го числа следующего месяца в 01:00
    repeat_interval => 'FREQ=MONTHLY; BYMONTHDAY=1; BYHOUR=1; BYMINUTE=0', -- Каждый месяц 1-го числа в 01:00
    enabled         => TRUE,
    comments        => 'Creates a new season at the beginning of each month.'
  );
  
  DBMS_OUTPUT.PUT_LINE('Job MONTHLY_SEASONS_JOB успешно создан.');
END;
/

