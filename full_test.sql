SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- == Удаляем старые тестовые игры перед запуском нового теста
-- =================================================================
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves WHERE game_id IN (SELECT game_id FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER')));
    DELETE FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER'));
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Тестовые партии и ходы очищены.');
END;
/

-- =================================================================
-- == ЭТАП 1: СОЗДАНИЕ И ПРИНЯТИЕ PvP ВЫЗОВА
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 1.1: Выполняется в сессии C##DEV_USER
-- -----------------------------------------------------------------
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color      => 'W'
    );
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.2: Выполняется в сессии C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.2: C##DEV2_USER ищет и принимает вызов ---');
    -- Ищем вызов, брошенный нам
    SELECT game_id INTO v_challenge_id
    FROM C##CHECKERS_APP.games
    WHERE status = 'CHALLENGED' AND (player_white_id = (SELECT player_id FROM C##CHECKERS_APP.players WHERE username=USER) OR player_black_id = (SELECT player_id FROM C##CHECKERS_APP.players WHERE username=USER))
    AND ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE('[INFO] Найден вызов с ID: ' || v_challenge_id || '. Присоединяемся...');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Вызов принят! Партия теперь АКТИВНА.');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '[INFO] Текущее состояние доски:');
    C##CHECKERS_APP.game_logic.print_board(p_game_id => v_challenge_id);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Прямых вызовов для ' || USER || ' не найдено!');
END;
/

-- =================================================================
-- == ЭТАП 2: ВЫПОЛНЕНИЕ ХОДОВ В PvP
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 2.1: Ход Белых (C##DEV_USER). Процедура сама найдет игру.
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.1: Ход Белых (C##DEV_USER) ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'c3-d4');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2.2: Ход Черных (C##DEV2_USER). Процедура сама найдет игру.
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.2: Ход Черных (C##DEV2_USER) ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'd6-c5');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 3: ЗАВЕРШЕНИЕ ПАРТИИ (RESIGN)
-- == Выполняется в сессии C##DEV_USER
-- =================================================================
BEGIN
    C##CHECKERS_APP.game_logic.resign_game();
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 4: ПРОСМОТР ЗАПИСИ ПАРТИИ (REPLAY)
-- =================================================================
DECLARE
    v_game_to_watch NUMBER;
BEGIN
    -- Найдем последнюю завершенную игру для просмотра
    SELECT game_id INTO v_game_to_watch FROM (
        SELECT game_id FROM C##CHECKERS_APP.games WHERE status NOT IN ('ACTIVE', 'OPEN', 'CHALLENGED') ORDER BY end_time DESC
    ) WHERE ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4: Просмотр записи партии ID: ' || v_game_to_watch || ' ---');
    C##CHECKERS_APP.game_logic.start_replay_session(p_game_id => v_game_to_watch);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Сессия просмотра начата.');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Показываем первые 3 хода ---');
    C##CHECKERS_APP.game_logic.show_next_replay_move(
        p_game_id       => v_game_to_watch,
        p_moves_to_show => 3
    );
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/


-- =================================================================
-- == ЭТАП 5: ИГРА ПРОТИВ КОМПЬЮТЕРА (PvE)
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 5.1: Создание игры против ИИ (выполняется в сессии C##DEV_USER)
-- -----------------------------------------------------------------
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'AI',
        p_player_color      => 'B'
    );
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 5.2: Ход против ИИ (выполняется в сессии C##DEV_USER)
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 5.2: Ход человека против ИИ ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'e3-f4');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;


-- Пример 3: Создание открытой игры
BEGIN
    C##CHECKERS_APP.game_logic.create_game();
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;



------------------------------------------------------------------
-- ПРОСМОТР ДОСКИ (print_board)
------------------------------------------------------------------
BEGIN
    C##CHECKERS_APP.game_logic.print_board();
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/