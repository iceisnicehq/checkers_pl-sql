SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- == Выполняется от имени C##CHECKERS_APP или SYSDBA
-- =================================================================
BEGIN
    -- Удаляем только те игры, которые были созданы тестовыми пользователями
    DELETE FROM C##CHECKERS_APP.game_moves WHERE game_id IN (SELECT game_id FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER')));
    DELETE FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER'));
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Тестовые партии и ходы очищены.');
END;
/

-- =================================================================
-- == ЭТАП 1: СОЗДАНИЕ И ПРИНЯТИЕ ВЫЗОВА
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 1.1: Выполняется в сессии C##DEV_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
    v_msg     VARCHAR2(1000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.1: C##DEV_USER создает прямой вызов для C##DEV2_USER ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color      => 'W',
        p_game_id           => v_game_id,
        p_status_message    => v_msg
    );
    DBMS_OUTPUT.PUT_LINE(v_msg);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.2: Выполняется в сессии C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.2: C##DEV2_USER ищет и принимает вызов ---');
    SELECT game_id INTO v_challenge_id
    FROM C##CHECKERS_APP.v_open_games
    WHERE challenged_player = USER AND ROWNUM = 1;
    DBMS_OUTPUT.PUT_LINE('[INFO] Найден вызов с ID: ' || v_challenge_id || '. Присоединяемся...');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Вызов принят! Партия теперь АКТИВНА.');
    DBMS_OUTPUT.PUT_LINE('[INFO] Текущее состояние доски:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_challenge_id));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Прямых вызовов для ' || USER || ' не найдено!');
END;
/

-- =================================================================
-- == ЭТАП 2: ВЫПОЛНЕНИЕ ХОДОВ
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 2.1: Выполняется в сессии C##DEV_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    v_game_id := C##CHECKERS_APP.game_logic.get_my_active_game();
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.1: Ход Белых (C##DEV_USER) ---');
        C##CHECKERS_APP.game_logic.make_move(
            p_game_id       => v_game_id,
            p_move_notation => 'c3-d4',
            p_status_message => v_status_message
        );
        DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] Активных партий для ' || USER || ' не найдено.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2.2: Выполняется в сессии C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    v_game_id := C##CHECKERS_APP.game_logic.get_my_active_game();
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.2: Ход Черных (C##DEV2_USER) ---');
        C##CHECKERS_APP.game_logic.make_move(
            p_game_id       => v_game_id,
            p_move_notation => 'd6-c5',
            p_status_message => v_status_message
        );
        DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после хода:');
        DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
    ELSE
         DBMS_OUTPUT.PUT_LINE('[INFO] Активных партий для ' || USER || ' не найдено.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 3: ЗАВЕРШЕНИЕ ПАРТИИ
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 3.1: C##DEV2_USER сдается
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
BEGIN
    v_game_id := C##CHECKERS_APP.game_logic.get_my_active_game();
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.1: C##DEV2_USER сдается в партии ' || v_game_id || ' ---');
        C##CHECKERS_APP.game_logic.resign_game(p_game_id => v_game_id);
        DBMS_OUTPUT.PUT_LINE('[OK] Партия завершена. C##DEV_USER победил.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] Нет активной партии, чтобы сдаться.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 4: ПРОСМОТР ЗАПИСИ ПАРТИИ (REPLAY)
-- == Может выполняться любым пользователем, например C##DEV_USER
-- =================================================================
-- =================================================================
-- == БЛОК 1: ЗАПУСК СЕССИИ ПРОСМОТРА
-- == Выполните этот блок один раз, чтобы начать.
-- =================================================================
SET SERVEROUTPUT ON;

DECLARE
    v_finished_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- ЗАПУСК СЕССИИ ПРОСМОТРА ---');
    
    -- Находим ID последней завершенной игры
    SELECT game_id INTO v_finished_game_id
    FROM C##CHECKERS_APP.v_player_history
    WHERE opponent_name = 'C##DEV2_USER' -- Укажите нужного оппонента
    ORDER BY start_time DESC FETCH FIRST 1 ROW ONLY;

    DBMS_OUTPUT.PUT_LINE('[INFO] Найдена завершенная партия ID: ' || v_finished_game_id);

    -- Начинаем сессию просмотра
    C##CHECKERS_APP.game_logic.start_replay_session(p_game_id => v_finished_game_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Сессия начата. Теперь можно просматривать ходы.');
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Не найдено завершенных партий для просмотра.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;

-- =================================================================
-- == БЛОК 2: ПОКАЗАТЬ СЛЕДУЮЩИЙ ХОД
-- == Выполняйте этот блок многократно для пошагового просмотра.
-- =================================================================
SET SERVEROUTPUT ON;

DECLARE
    v_finished_game_id NUMBER;
BEGIN
    -- Находим ID последней игры (чтобы не вводить его вручную каждый раз)
    SELECT game_id INTO v_finished_game_id
    FROM C##CHECKERS_APP.v_player_history
    WHERE opponent_name = 'C##DEV2_USER'
    ORDER BY start_time DESC FETCH FIRST 1 ROW ONLY;
    
    -- Показываем следующий ход
    C##CHECKERS_APP.game_logic.show_next_replay_move(p_game_id => v_finished_game_id);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Не найдено завершенных партий.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;

-- =================================================================
-- == БЛОК 3: ПОКАЗАТЬ ПЕРВЫЕ 10 ХОДОВ В ЦИКЛЕ
-- == Выполните этот блок, чтобы увидеть автоматический просмотр.
-- =================================================================
SET SERVEROUTPUT ON;

DECLARE
    v_finished_game_id NUMBER;
    v_total_moves      NUMBER;
    v_moves_to_show    NUMBER := 10;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- ПРОСМОТР ' || v_moves_to_show || ' ХОДОВ В ЦИКЛЕ ---');
    
    -- Находим игру и количество ходов в ней
    SELECT game_id, total_moves INTO v_finished_game_id, v_total_moves
    FROM C##CHECKERS_APP.v_player_history
    WHERE opponent_name = 'C##DEV2_USER'
    ORDER BY start_time DESC FETCH FIRST 1 ROW ONLY;

    DBMS_OUTPUT.PUT_LINE('[INFO] Перезапускаем сессию для игры ID: ' || v_finished_game_id);
    
    -- Перезапускаем сессию, чтобы начать с 1-го хода
    C##CHECKERS_APP.game_logic.start_replay_session(p_game_id => v_finished_game_id);
    
    FOR i IN 1..v_moves_to_show LOOP
        IF i > v_total_moves THEN EXIT; END IF;
        C##CHECKERS_APP.game_logic.show_next_replay_move(p_game_id => v_finished_game_id);
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('-- Просмотр в цикле завершен --');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Не найдено завершенных партий для просмотра.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;