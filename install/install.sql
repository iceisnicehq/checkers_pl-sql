-- Порядок Действий (Резюме)
--     1. Один раз (как SYS): Запустить setup_users.sql для создания всех нужных аккаунтов.
--     2. Один раз (как C##CHECKERS_APP): Запустить install.sql для создания всех таблиц, пакетов и т.д.
--     3. Один раз (как C##CHECKERS_APP): Запустить setup_permissions.sql для публикации API.


-- setup_users.sql
-- =================================================================
-- == Создание пользователей и выдача системных привилегий (SYS) ==
-- =================================================================
-- Выполнять из-под пользователя SYS.

-- Отключаем требование префикса C## для Oracle 12c+ (если применимо и разрешено политикой)
-- ALTER SESSION SET "_ORACLE_SCRIPT"=true;

-- 1. Создание пользователя-владельца приложения
CREATE USER C##CHECKERS_APP IDENTIFIED BY "P@ssw0rd";

-- Выдача прав на создание сессии, таблиц, представлений, процедур и т.д.
GRANT CONNECT, RESOURCE TO C##CHECKERS_APP;
GRANT CREATE VIEW TO C##CHECKERS_APP;
GRANT CREATE SEQUENCE TO C##CHECKERS_APP;
GRANT CREATE JOB TO C##CHECKERS_APP;

-- Даем квоту на табличное пространство (замените USERS на ваше)
ALTER USER C##CHECKERS_APP QUOTA UNLIMITED ON USERS;

-- 2. Создание пользователей-игроков (пример)
-- CREATE USER C##DEV_USER IDENTIFIED BY "P@ssw0rd";
GRANT CONNECT TO C##DEV_USER;
ALTER USER C##DEV_USER QUOTA UNLIMITED ON USERS;

-- CREATE USER C##DEV2_USER IDENTIFIED BY "P@ssw0rd";
GRANT CONNECT TO C##DEV2_USER;
ALTER USER C##DEV2_USER QUOTA UNLIMITED ON USERS;


-- install.sql
-- =================================================================
-- == Главный установочный скрипт приложения "Шашки"             ==
-- =================================================================
-- Выполнять из-под пользователя-владельца C##CHECKERS_APP.


@tables.sql

@views.sql

@game_logic.pks

@game_logic.pkb




-- setup_permissions.sql
-- =================================================================
-- == Выдача публичных прав на объекты приложения                 ==
-- =================================================================
-- Выполнять из-под пользователя-владельца C##CHECKERS_APP.

-- Даем право выполнять пакет ВСЕМ пользователям в базе данных
GRANT EXECUTE ON game_logic TO PUBLIC;

-- Даем право просматривать лобби ВСЕМ пользователям
GRANT SELECT ON v_open_games TO PUBLIC;
GRANT SELECT ON v_active_games TO PUBLIC;
GRANT SELECT ON v_game_protocol TO PUBLIC;
GRANT SELECT ON v_player_history TO PUBLIC;
GRANT SELECT ON v_leaderboard TO PUBLIC;