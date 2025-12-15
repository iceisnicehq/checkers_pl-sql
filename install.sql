-- ====================================================================
-- Скрипт установки прав доступа для игры "Шашки"
-- ====================================================================
-- 
-- ВАЖНО: Этот скрипт должен выполняться ПОСЛЕ полной установки системы:
-- 
-- Порядок установки:
-- 1. Создание таблиц (папка tables/):
--    - Выполнить все скрипты из папки tables/ в порядке нумерации:
--      * 01_players.sql
--      * 02_game_rules.sql
--      * 03_seasons.sql
--      * 04_player_ratings.sql
--      * 05_matches.sql
--      * 06_puzzles.sql
--      * 07_games.sql
--      * 08_game_moves.sql
--      * 09_daily_puzzles.sql
--      * 10_audit_log.sql
--      * 11_spectators.sql
--      * 12_indexes.sql (индексы создаются после всех таблиц)
-- 
-- 2. Наполнение базы данных:
--    - Скрипты наполнения находятся в тех же файлах таблиц (INSERT INTO ...)
--    - Правила игры, начальные задачи и т.д. создаются автоматически
-- 
-- 3. Создание спецификации пакета:
--    - Выполнить pks/game_logic.pks
-- 
-- 4. Создание тела пакета:
--    - Выполнить pkb/game_logic.pkb
-- 
-- 5. Создание триггеров (папка triggers/):
--    - 01_trg_init_player_ratings.sql
--    - 02_trg_init_season_ratings.sql
-- 
-- 6. Создание автоматических заданий (schedulers, папка schedulers/):
--    - daily_puzzle_job.sql
--    - monthly_seasons_job.sql
--    - inactive_sessions_timeout.sql
-- 
-- 7. Создание представлений (views, папка views/):
--    - Выполнить все скрипты из папки views/:
--      * v_game_rules.sql
--      * v_open_games.sql
--      * v_active_games.sql
--      * v_ended_games.sql
--      * v_game_protocol.sql
--      * v_player_history.sql
--      * v_player_ratings.sql
--      * v_daily_puzzle_results.sql
--      * v_active_matches.sql
--      * v_open_matches.sql
--      * v_ended_matches.sql
--      * v_match_details.sql
-- 
-- 8. Установка прав доступа (этот файл):
--    - Выполнить install.sql для предоставления прав другим пользователям
--
-- 9. Создание тестовых пользователей:
--    Для тестирования игры необходимо создать 5 тестовых пользователей:
--    - PLAYER1, PLAYER2, PLAYER3, PLAYER4 – для игры друг с другом (PvP)
--    - PLAYER5 – для просмотра игр других пользователей (режим наблюдателя)
--    
--    Пароль для всех пользователей: P@ssw0rd
--    
--    Пример создания пользователей (выполняется от имени администратора):
--    CREATE USER player1 IDENTIFIED BY "P@ssw0rd";
--    CREATE USER player2 IDENTIFIED BY "P@ssw0rd";
--    CREATE USER player3 IDENTIFIED BY "P@ssw0rd";
--    CREATE USER player4 IDENTIFIED BY "P@ssw0rd";
--    CREATE USER player5 IDENTIFIED BY "P@ssw0rd";
--    
--    GRANT CONNECT, RESOURCE TO player1, player2, player3, player4, player5;
--
-- ====================================================================

-- Предоставление прав на выполнение пакета game_logic всем пользователям
GRANT EXECUTE ON game_logic TO PUBLIC;

-- Предоставление прав на чтение представлений (views) всем пользователям
GRANT SELECT ON v_game_rules TO PUBLIC;
GRANT SELECT ON v_open_games TO PUBLIC;
GRANT SELECT ON v_active_games TO PUBLIC;
GRANT SELECT ON v_ended_games TO PUBLIC;
GRANT SELECT ON v_game_protocol TO PUBLIC;
GRANT SELECT ON v_player_history TO PUBLIC;
GRANT SELECT ON v_player_ratings TO PUBLIC;
GRANT SELECT ON v_daily_puzzle_results TO PUBLIC;
GRANT SELECT ON v_active_matches TO PUBLIC;
GRANT SELECT ON v_open_matches TO PUBLIC;
GRANT SELECT ON v_ended_matches TO PUBLIC;
GRANT SELECT ON v_match_details TO PUBLIC;