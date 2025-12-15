BEGIN
    FOR i IN (
        SELECT 'DROP VIEW ' || view_name AS stmt 
        FROM user_views
        WHERE view_name IN (
            'V_ACTIVE_GAMES', 'V_ACTIVE_MATCHES', 'V_DAILY_PUZZLE_RESULTS',
            'V_ENDED_GAMES', 'V_ENDED_MATCHES', 'V_GAME_PROTOCOL',
            'V_MATCH_DETAILS', 'V_OPEN_GAMES', 'V_OPEN_MATCHES',
            'V_PLAYER_HISTORY', 'V_PLAYER_RATINGS', 'V_GAME_RULES'
        )
    ) LOOP
        EXECUTE IMMEDIATE i.stmt;
    END LOOP;
END;

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE BODY game_logic';
    EXECUTE IMMEDIATE 'DROP PACKAGE game_logic';
END;

BEGIN
    FOR i IN (
        SELECT 'DROP TRIGGER ' || trigger_name AS stmt 
        FROM user_triggers
        WHERE trigger_name IN (
            'TRG_INIT_PLAYER_RATINGS', 'TRG_INIT_SEASON_RATINGS'
        )
    ) LOOP
        EXECUTE IMMEDIATE i.stmt;
    END LOOP;
END;

BEGIN
    FOR i IN (
        SELECT job_name FROM user_scheduler_jobs
        WHERE job_name IN (
            'DAILY_CHECKERS_PUZZLE_JOB',
            'INACTIVE_SESSIONS_TIMEOUT_JOB',
            'MONTHLY_SEASONS_JOB'
        )
    ) LOOP
        DBMS_SCHEDULER.DROP_JOB(job_name => i.job_name, force => TRUE);
    END LOOP;

    FOR i IN (
        SELECT job_name FROM user_scheduler_jobs
        WHERE job_name LIKE 'MOVE_TIMEOUT_JOB_%'
    ) LOOP
        DBMS_SCHEDULER.DROP_JOB(job_name => i.job_name, force => TRUE);
    END LOOP;
END;

BEGIN
    FOR i IN (
        SELECT 'DROP TABLE ' || table_name || ' CASCADE CONSTRAINTS PURGE' AS stmt 
        FROM user_tables
        WHERE table_name IN (
            'PLAYERS', 'GAME_RULES', 'SEASONS', 'PLAYER_RATINGS', 'MATCHES', 'GAMES',
            'GAME_MOVES', 'PUZZLES', 'DAILY_PUZZLES', 'AUDIT_LOG', 'SPECTATORS'
        )
    ) LOOP
        EXECUTE IMMEDIATE i.stmt;
    END LOOP;
END;

BEGIN
    FOR i IN (
        SELECT 'DROP SEQUENCE ' || sequence_name AS stmt 
        FROM user_sequences
    ) LOOP
        EXECUTE IMMEDIATE i.stmt;
    END LOOP;
END;

BEGIN
    FOR i IN (
        SELECT username FROM all_users
        WHERE username IN ('PLAYER1', 'PLAYER2', 'PLAYER3', 'PLAYER4', 'PLAYER5')
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP USER ' || i.username || ' CASCADE';
            DBMS_OUTPUT.PUT_LINE('Пользователь ' || i.username || ' удален.');
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Ошибка при удалении пользователя ' || i.username || ': ' || SQLERRM);
        END;
    END LOOP;
END;

BEGIN
    DBMS_OUTPUT.PUT_LINE('Очистка завершена. Все объекты удалены.');
END;
