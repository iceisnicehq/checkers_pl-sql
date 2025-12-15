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
        WHERE sequence_name LIKE 'REPLAY_SEQ_%'
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE i.stmt;
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Ошибка при удалении sequence ' || i.stmt || ': ' || SQLERRM);
        END;
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

-- ====================================================================
-- Проверка успешного удаления всех объектов
-- ====================================================================
-- 
-- После выполнения скрипта uninstall.sql выполните следующие запросы
-- для проверки, что все объекты действительно удалены:
--
-- 1. Проверка представлений (views):
--    SELECT COUNT(*) FROM user_views 
--    WHERE view_name IN (
--        'V_ACTIVE_GAMES', 'V_ACTIVE_MATCHES', 'V_DAILY_PUZZLE_RESULTS',
--        'V_ENDED_GAMES', 'V_ENDED_MATCHES', 'V_GAME_PROTOCOL',
--        'V_MATCH_DETAILS', 'V_OPEN_GAMES', 'V_OPEN_MATCHES',
--        'V_PLAYER_HISTORY', 'V_PLAYER_RATINGS', 'V_GAME_RULES'
--    );
--    Ожидаемый результат: 0
--
-- 2. Проверка пакета:
--    SELECT COUNT(*) FROM user_objects 
--    WHERE object_name = 'GAME_LOGIC' AND object_type IN ('PACKAGE', 'PACKAGE BODY');
--    Ожидаемый результат: 0
--
-- 3. Проверка триггеров:
--    SELECT COUNT(*) FROM user_triggers 
--    WHERE trigger_name IN ('TRG_INIT_PLAYER_RATINGS', 'TRG_INIT_SEASON_RATINGS');
--    Ожидаемый результат: 0
--
-- 4. Проверка автоматических заданий (schedulers):
--    SELECT COUNT(*) FROM user_scheduler_jobs 
--    WHERE job_name IN (
--        'DAILY_CHECKERS_PUZZLE_JOB',
--        'INACTIVE_SESSIONS_TIMEOUT_JOB',
--        'MONTHLY_SEASONS_JOB'
--    ) OR job_name LIKE 'MOVE_TIMEOUT_JOB_%';
--    Ожидаемый результат: 0
--
-- 5. Проверка таблиц:
--    SELECT COUNT(*) FROM user_tables 
--    WHERE table_name IN (
--        'PLAYERS', 'GAME_RULES', 'SEASONS', 'PLAYER_RATINGS', 'MATCHES', 'GAMES',
--        'GAME_MOVES', 'PUZZLES', 'DAILY_PUZZLES', 'AUDIT_LOG', 'SPECTATORS'
--    );
--    Ожидаемый результат: 0
--
-- 6. Проверка последовательностей (sequences):
--    SELECT COUNT(*) FROM user_sequences;
--    Ожидаемый результат: 0 (или количество других sequences, не связанных с игрой)
--
-- 7. Проверка тестовых пользователей (требуются права DBA):
--    SELECT COUNT(*) FROM all_users 
--    WHERE username IN ('PLAYER1', 'PLAYER2', 'PLAYER3', 'PLAYER4', 'PLAYER5');
--    Ожидаемый результат: 0
--
-- ====================================================================
