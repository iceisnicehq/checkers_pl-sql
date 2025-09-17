-- =================================================================
-- == Скрипт-шаблон для настройки окружения нового игрока        ==
-- =================================================================
-- Выполнять из-под пользователя SYS.

-- Замените C##NEW_PLAYER на реальное имя пользователя
DEFINE player_name = 'C##DEV_USER'

PROMPT [SYNONYM] Creating synonyms for player: &player_name...

-- Создаем синонимы в схеме игрока, чтобы ему не нужно было писать префикс C##CHECKERS_APP
-- Для этого подключаемся временно под игроком
CONNECT &player_name/your_player_password;

CREATE OR REPLACE SYNONYM game_logic FOR C##CHECKERS_APP.game_logic;
CREATE OR REPLACE SYNONYM v_open_games FOR C##CHECKERS_APP.v_open_games;

PROMPT [SUCCESS] Synonyms for &player_name created. Player is ready.