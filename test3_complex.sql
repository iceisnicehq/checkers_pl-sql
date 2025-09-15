-- =================================================================
-- == КОМПЛЕКСНЫЙ ТЕСТОВЫЙ СЦЕНАРИЙ ДЛЯ ЛОББИ ИГРЫ "ШАШКИ"       ==
-- ==             (Версия для общей схемы C##CHECKERS_APP)         ==
-- =================================================================
SET SERVEROUTPUT ON;
SET LONG 20000;
-- Отключаем проверку подстановочных переменных, чтобы символ '&' не вызывал диалог
SET DEFINE OFF;

-- -----------------------------------------------------------------
-- ШАГ 0: (Опционально) Полная очистка для нового теста
-- Подключитесь как C##CHECKERS_APP и выполните этот блок.
-- -----------------------------------------------------------------
PROMPT [INFO] Performing cleanup for a fresh test run...
-- У игроков нет прав на удаление, поэтому это должен делать владелец схемы.
-- CONNECT C##CHECKERS_APP/your_password_here;
DELETE FROM C##CHECKERS_APP.game_moves;
DELETE FROM C##CHECKERS_APP.games;
-- Игроков можно не удалять, они переиспользуются.
COMMIT;
PROMPT [INFO] Cleanup complete.


-- -----------------------------------------------------------------
-- ШАГ 1: C##DEV_USER создает ОТКРЫТЫЙ вызов
-- Подключитесь как C##DEV_USER и выполните этот блок.
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ШАГ 1: C##DEV_USER создает ОТКРЫТЫЙ вызов ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_player_color => 'W', -- Хочет играть за белых
        p_game_id      => v_game_id
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Открытый вызов создан. Game ID: ' || v_game_id);
    COMMIT;
END;
/


-- -----------------------------------------------------------------
-- ШАГ 2: C##DEV2_USER смотрит список открытых игр
-- Подключитесь как C##DEV2_USER и выполните этот блок.
-- -----------------------------------------------------------------
PROMPT --- ШАГ 2: C##DEV2_USER смотрит лобби ---
PROMPT [INFO] Ожидается увидеть одну игру с типом 'Open Challenge'...
SELECT * FROM C##CHECKERS_APP.v_open_games;


-- -----------------------------------------------------------------
-- ШАГ 3: C##DEV_USER создает ПРЯМОЙ вызов для C##DEV2_USER
-- Подключитесь как C##DEV_USER и выполните этот блок.
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ШАГ 3: C##DEV_USER создает ПРЯМОЙ вызов ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_game_id           => v_game_id
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Прямой вызов для C##DEV2_USER создан. Game ID: ' || v_game_id);
    COMMIT;
END;
/


-- -----------------------------------------------------------------
-- ШАГ 4: C##DEV2_USER снова смотрит список игр
-- Подключитесь как C##DEV2_USER и выполните этот блок.
-- -----------------------------------------------------------------
PROMPT --- ШАГ 4: C##DEV2_USER снова смотрит лобби ---
PROMPT [INFO] Ожидается увидеть две игры: одну открытую, одну прямую...
SELECT * FROM C##CHECKERS_APP.v_open_games;

PROMPT [INFO] ...а теперь только те, что адресованы лично C##DEV2_USER:
SELECT * FROM C##CHECKERS_APP.v_open_games WHERE challenged_player = USER;


-- -----------------------------------------------------------------
-- ШАГ 5: C##DEV2_USER принимает ПРЯМОЙ вызов
-- Подключитесь как C##DEV2_USER и выполните этот блок.
-- -----------------------------------------------------------------
DECLARE
    v_direct_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ШАГ 5: C##DEV2_USER принимает ПРЯМОЙ вызов ---');
    -- Находим ID прямого вызова
    SELECT game_id INTO v_direct_challenge_id
    FROM C##CHECKERS_APP.v_open_games
    WHERE challenged_player = USER AND ROWNUM = 1;

    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_direct_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Вызов принят! Партия ' || v_direct_challenge_id || ' теперь АКТИВНА.');
    COMMIT;
END;
/


-- -----------------------------------------------------------------
-- ШАГ 6: Проверка финального состояния
-- Подключитесь как C##CHECKERS_APP (или любой пользователь с правами DBA) для полного обзора.
-- -----------------------------------------------------------------
PROMPT --- ШАГ 6: Проверка финального состояния ---
PROMPT [INFO] Состояние таблицы games (ожидается одна WAITING, одна ACTIVE):
SELECT
    g.game_id,
    g.status,
    (SELECT username FROM C##CHECKERS_APP.players p WHERE p.player_id = g.player_white_id) as white_player,
    (SELECT username FROM C##CHECKERS_APP.players p WHERE p.player_id = g.player_black_id) as black_player
FROM C##CHECKERS_APP.games g
ORDER BY g.game_id;

PROMPT [INFO] Оставшиеся игры в лобби (ожидается одна 'Open Challenge'):
SELECT * FROM C##CHECKERS_APP.v_open_games;

PROMPT [INFO] Доска в активной партии:
DECLARE
    v_active_game_id NUMBER;
    v_board          CLOB;
BEGIN
    SELECT game_id INTO v_active_game_id
    FROM C##CHECKERS_APP.games WHERE status = 'ACTIVE' AND ROWNUM = 1;

    v_board := C##CHECKERS_APP.game_logic.get_printable_board(v_active_game_id);
    DBMS_OUTPUT.PUT_LINE(v_board);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Активных партий не найдено.');
END;
/