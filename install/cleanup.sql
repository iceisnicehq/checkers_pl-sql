-- =============================================================================
-- Файл: cleanup.sql
-- Описание: Скрипт для очистки существующих объектов БД.
-- =============================================================================

BEGIN
    FOR i IN (SELECT 'DROP TABLE ' || table_name || ' CASCADE CONSTRAINTS PURGE' AS stmt FROM user_tables
              WHERE table_name IN (
                'PLAYERS', 'GAME_RULES', 'SEASONS', 'PLAYER_RATINGS', 'MATCHES', 'GAMES',
                'GAME_MOVES', 'PUZZLES', 'DAILY_PUZZLES', 'AUDIT_LOG', 'SPECTATORS'
              )) LOOP
        EXECUTE IMMEDIATE i.stmt;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN
            RAISE;
        END IF;
END;
/

BEGIN
  DBMS_SCHEDULER.DROP_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -27475 THEN
            RAISE;
        END IF;
END;
/
