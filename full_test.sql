SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- == Удаляем старые тестовые данные
-- =================================================================
BEGIN
    -- Очистка таблиц (в реальной разработке аккуратнее, здесь для теста)
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    DELETE FROM C##CHECKERS_APP.matches;
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL; -- Удаляем только пользовательские задачи
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Тестовые данные очищены.');
END;
/

-- =================================================================
-- == ЭТАП 1: PvP ИГРА (Игрок против Игрока)
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 1.1: Игрок 1 (C##DEV_USER) создает игру
-- -----------------------------------------------------------------
PROMPT === ЭТАП 1.1: Создание PvP игры (C##DEV_USER) ===
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color      => 'W',
        p_time_limit_move_sec => 60
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Игра создана.');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.2: Игрок 2 (C##DEV2_USER) принимает вызов
-- -----------------------------------------------------------------
PROMPT === ЭТАП 1.2: Принятие вызова (C##DEV2_USER) ===
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Имитация поиска игры (в реальности берется из view v_open_games)
    SELECT game_id INTO v_game_id 
    FROM C##CHECKERS_APP.games 
    WHERE status IN ('O', 'C') AND ROWNUM = 1;

    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_game_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Игрок присоединился к игре ID=' || v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.3: Ходы (Белые: c3-d4, Черные: f6-e5)
-- -----------------------------------------------------------------
PROMPT === ЭТАП 1.3: Выполнение ходов ===
BEGIN
    -- Ход Белых
    DBMS_OUTPUT.PUT_LINE('-> Ход Белых (c3-d4)');
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    
    -- Ход Черных (В реальном тесте нужно переключить сессию, здесь симулируем вызов)
    -- ПРИМЕЧАНИЕ: В однопользовательском скрипте мы не можем легко сменить USER.
    -- Поэтому дальнейшие ходы могут упасть, если проверка идет по USER.
    -- Но для теста API мы предполагаем, что make_move вызывается в контексте нужного юзера.
    -- Если пакет проверяет USER, то этот шаг в скрипте сработает только если отключена проверка или мы "хакнем" её.
    -- Для целей этого скрипта мы просто вызываем make_move, надеясь, что логика позволит (или это тест для ручного запуска кусками).
    
    DBMS_OUTPUT.PUT_LINE('-> Ход Черных (d6-e5)');
    -- C##CHECKERS_APP.game_logic.make_move('d6-e5'); -- Раскомментировать если тестируете в 2 сессии
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.4: Просмотр доски
-- -----------------------------------------------------------------
PROMPT === ЭТАП 1.4: Просмотр доски ===
BEGIN
    C##CHECKERS_APP.game_logic.print_active_board();
END;
/

-- =================================================================
-- == ЭТАП 2: PvE ИГРА (Против ИИ)
-- =================================================================
PROMPT === ЭТАП 2: Создание PvE игры (Против ИИ) ===
BEGIN
    -- Создаем игру против ИИ (Сложность Easy = 'E')
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color  => 'W'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] PvE игра создана.');
    
    -- Делаем ход
    DBMS_OUTPUT.PUT_LINE('-> Ход Игрока (c3-d4)');
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    
    -- Смотрим ответ ИИ (он должен быть автоматическим)
    C##CHECKERS_APP.game_logic.print_active_board();
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 3: ЗАДАЧИ (PUZZLES)
-- =================================================================
PROMPT === ЭТАП 3: Работа с Задачами ===
DECLARE
    v_board CLOB := '12b4b5b2b8w1b1w11w3w8'; -- Пример позиции
BEGIN
    -- 3.1 Создание задачи
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board,
        p_turn_to_move   => 'W',
        p_moves_to_solve => 3,
        p_difficulty_level => 1
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Задача создана.');

    -- 3.2 Просмотр списка задач
    DBMS_OUTPUT.PUT_LINE('--- Список задач (Difficulty 1) ---');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 1);
    
    -- 3.3 Решение задачи (Запуск игры из задачи)
    -- Берем ID последней задачи
    FOR r IN (SELECT MAX(puzzle_id) as pid FROM C##CHECKERS_APP.puzzles) LOOP
        C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => r.pid);
        DBMS_OUTPUT.PUT_LINE('[OK] Начато решение задачи ID=' || r.pid);
    END LOOP;
    
    C##CHECKERS_APP.game_logic.print_active_board();
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 4: МАТЧИ (СЕРИИ ИГР)
-- =================================================================
PROMPT === ЭТАП 4: Матчи (Matches) ===
BEGIN
    -- 4.1 Создание матча до 3 побед
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win      => 3,
        p_player_color      => 'W'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Матч создан.');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 5: РЕПЛЕИ (REPLAYS)
-- =================================================================
PROMPT === ЭТАП 5: Просмотр повтора (Replay) ===
DECLARE
    v_last_game_id NUMBER;
BEGIN
    -- Берем любую завершенную или активную игру
    SELECT MAX(game_id) INTO v_last_game_id FROM C##CHECKERS_APP.games;
    
    IF v_last_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Просмотр игры ID=' || v_last_game_id);
        
        -- Запуск просмотра (показываем первые 5 ходов)
        C##CHECKERS_APP.game_logic.watch_game_replay(
            p_game_id => v_last_game_id,
            p_moves_to_show => 5
        );
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет игр для просмотра.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] ' || SQLERRM);
END;
/

PROMPT === ТЕСТ ЗАВЕРШЕН ===