BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'INACTIVE_SESSIONS_TIMEOUT_JOB');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'INACTIVE_SESSIONS_TIMEOUT_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN C##CHECKERS_APP.game_logic.p_process_inactive_timeouts(p_timeout_hours => 24); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=HOURLY; BYMINUTE=0',
    enabled         => TRUE,
    comments        => 'Автоматически закрывает неактивные игровые сессии после периода таймаута.'
  );
  
  DBMS_OUTPUT.PUT_LINE('Job INACTIVE_SESSIONS_TIMEOUT_JOB успешно создан.');
END;

