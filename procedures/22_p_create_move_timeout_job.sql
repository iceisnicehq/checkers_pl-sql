-- @procedure p_create_move_timeout_job
-- @brief Creates a scheduler job to timeout a move if time limit is exceeded
PROCEDURE p_create_move_timeout_job(p_game_id IN NUMBER) IS
    v_job_name VARCHAR2(128);
    v_time_limit NUMBER;
BEGIN
    -- Получаем лимит времени на ход
    SELECT time_limit_move_sec INTO v_time_limit
    FROM games
    WHERE game_id = p_game_id;
    
    -- Если лимита нет, джоб не нужен
    IF v_time_limit IS NULL THEN
        RETURN;
    END IF;
    
    v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;
    
    -- Удаляем старый джоб если есть
    BEGIN
        DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE);
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;
    
    -- Создаем новый джоб
    DBMS_SCHEDULER.CREATE_JOB(
        job_name   => v_job_name,
        job_type   => 'PLSQL_BLOCK',
        job_action => 'DECLARE
                v_game games%ROWTYPE;
                v_loser_color CHAR(1);
            BEGIN
                SELECT * INTO v_game FROM games WHERE game_id = ' || p_game_id || ' FOR UPDATE;
                
                -- Проверяем что игра еще активна
                IF v_game.status = ''A'' THEN
                    -- Проигравший - тот, чей сейчас ход
                    v_loser_color := v_game.current_turn;
                    
                    UPDATE games
                    SET status = ''T'', -- Timeout
                        end_time = SYSDATE,
                        winner_player_color = CASE v_loser_color WHEN ''W'' THEN ''B'' ELSE ''W'' END
                    WHERE game_id = ' || p_game_id || ';
                    
                    UPDATE spectators SET left_at = SYSDATE 
                    WHERE game_id = ' || p_game_id || ' AND left_at IS NULL;
                    
                    C##CHECKERS_APP.game_logic.p_update_ratings(' || p_game_id || ');
                    C##CHECKERS_APP.game_logic.p_audit_log(NULL, ' || p_game_id || ', ''MOVE_TIMEOUT'');
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;',
        start_date => SYSTIMESTAMP + (v_time_limit / 86400), -- Через time_limit_move_sec секунд
        enabled    => TRUE,
        auto_drop  => TRUE,
        comments   => 'Move timeout job for game ' || p_game_id
    );
EXCEPTION
    WHEN OTHERS THEN NULL; -- Игнорируем ошибки создания джоба
END p_create_move_timeout_job;

