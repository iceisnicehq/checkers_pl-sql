-- @procedure p_drop_move_timeout_job
-- @brief Drops the move timeout job when game ends
PROCEDURE p_drop_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
BEGIN
    BEGIN
        DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
END p_drop_move_timeout_job;

