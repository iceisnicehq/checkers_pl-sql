PROCEDURE p_reschedule_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128);
    v_time_limit NUMBER;
BEGIN
    SELECT time_limit_move_sec INTO v_time_limit
    FROM games
    WHERE game_id = p_game_id;
    
    IF v_time_limit IS NULL THEN
        RETURN;
    END IF;
    
    v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;
    
    BEGIN
        DBMS_SCHEDULER.SET_ATTRIBUTE(
            name      => v_job_name,
            attribute => 'start_date',
            value     => SYSTIMESTAMP + (v_time_limit / 86400)
        );
    EXCEPTION
        WHEN OTHERS THEN NULL;
            p_create_move_timeout_job(p_game_id);
    END;
EXCEPTION
    WHEN OTHERS THEN NULL;
END p_reschedule_move_timeout_job;
