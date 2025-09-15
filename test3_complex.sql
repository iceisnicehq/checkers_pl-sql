-- =================================================================
-- == КОМПЛЕКСНЫЙ ТЕСТОВЫЙ СЦЕНАРИЙ ДЛЯ ЛОББИ ИГРЫ "ШАШКИ" ==
-- =================================================================
SET SERVEROUTPUT ON;
SET LONG 20000;

-- -----------------------------------------------------------------
-- ШАГ 0: (Опционально) Полная очистка для нового теста
-- Выполните от имени любого из пользователей.
-- -----------------------------------------------------------------
PROMPT [INFO] Performing cleanup for a fresh test run...
DELETE FROM game_moves;
DELETE FROM games;
COMMIT;
PROMPT [INFO] Cleanup complete.

-- -----------------------------------------------------------------
-- ШАГ 1: C##DEV_USER создает ОТКРЫТЫЙ вызов
-- Выполните этот блок, подключившись как C##DEV_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- ШАГ 1: C##DEV_USER создает ОТКРЫТЫЙ вызов ---');
    game_logic.create_game(
        p_player_color => 'W', -- Хочет играть за белых
        p_game_id      => v_game_id
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Открытый вызов создан. Game ID: ' || v_game_id);
    COMMIT;
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2: C##DEV2_USER смотрит список открытых игр
-- Выполните этот блок, подключившись как C##DEV2_USER
-- -----------------------------------------------------------------
PROMPT --- ШАГ 2: C##DEV2_USER смотрит лобби ---
PROMPT [INFO] Ожидается увидеть одну игру с типом 'Open Challenge'...
SELECT * FROM v_open_games;


-- -----------------------------------------------------------------
-- ШАГ 3: C##DEV_USER создает ПРЯМОЙ вызов для C##DEV2_USER
-- Выполните этот блок, подключившись как C##DEV_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ШАГ 3: C##DEV_USER создает ПРЯМОЙ вызов ---');
    game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_game_id           => v_game_id
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Прямой вызов для C##DEV2_USER создан. Game ID: ' || v_game_id);
    COMMIT;
END;
/


-- -----------------------------------------------------------------
-- ШАГ 4: C##DEV2_USER снова смотрит список игр
-- Выполните этот блок, подключившись как C##DEV2_USER
-- -----------------------------------------------------------------
PROMPT --- ШАГ 4: C##DEV2_USER снова смотрит лобби ---
PROMPT [INFO] Ожидается увидеть две игры: одну открытую, одну прямую...
SELECT * FROM v_open_games;

PROMPT [INFO] ...а теперь только те, что адресованы лично C##DEV2_USER:
SELECT * FROM v_open_games WHERE challenged_player = USER;


-- -----------------------------------------------------------------
-- ШАГ 5: C##DEV2_USER принимает ПРЯМОЙ вызов
-- Выполните этот блок, подключившись как C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_direct_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ШАГ 5: C##DEV2_USER принимает ПРЯМОЙ вызов ---');
    -- Находим ID прямого вызова
    SELECT game_id INTO v_direct_challenge_id
    FROM v_open_games
    WHERE challenged_player = USER AND ROWNUM = 1;

    game_logic.join_game(p_game_id => v_direct_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Вызов принят! Партия ' || v_direct_challenge_id || ' теперь АКТИВНА.');
    COMMIT;
END;
/


-- -----------------------------------------------------------------
-- ШАГ 6: Проверка финального состояния
-- Выполните от имени любого из пользователей.
-- -----------------------------------------------------------------
PROMPT --- ШАГ 6: Проверка финального состояния ---
PROMPT [INFO] Состояние таблицы games (одна WAITING, одна ACTIVE):
SELECT game_id, status, (SELECT username FROM players WHERE player_id = g.player_white_id) as white, (SELECT username FROM players WHERE player_id = g.player_black_id) as black
FROM games g
ORDER BY game_id;

PROMPT [INFO] Доска в активной партии:
DECLARE
    v_active_game_id NUMBER;
BEGIN
    SELECT game_id INTO v_active_game_id FROM games WHERE status = 'ACTIVE';
    DBMS_OUTPUT.PUT_LINE(game_logic.get_printable_board(v_active_game_id));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Активных партий не найдено.');
END;
