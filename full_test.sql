-- Comprehensive Test Script for Checkers Application
SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;
SET VERIFY OFF; -- Hides substitution variable prompts for cleaner output

-- Use a variable to hold the ID of the game being tested in PvP
COLUMN game_id_pvp NEW_VALUE game_id_pvp_val
SELECT 0 game_id_pvp FROM DUAL;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- =================================================================
BEGIN
    -- Clean up test games
    DELETE FROM C##CHECKERS_APP.game_moves WHERE game_id IN (SELECT game_id FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER')));
    DELETE FROM C##CHECKERS_APP.games WHERE creator_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER')));
    
    -- Clean up puzzle attempts and custom puzzles
    DELETE FROM C##CHECKERS_APP.puzzle_attempts WHERE player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER'));
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IN (SELECT player_id FROM C##CHECKERS_APP.players WHERE username IN ('C##DEV_USER', 'C##DEV2_USER'));
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] All previous test games and puzzle attempts have been cleared.');
END;
/

-- =================================================================
-- == ЭТАП 1: ИГРА ПРОТИВ КОМПЬЮТЕРА (PvE)
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 1.1: C##DEV_USER создает игру против ИИ (Сложность 0, играет за Белых)
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.1: Создание игры против ИИ (Сложность 0, Белые) ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 0,       -- << ИЗМЕНЕНО: Задаем сложность ИИ
        p_player_color  => 'W'       -- Играем за белых
    );
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.2: C##DEV_USER делает ход
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.2: Ход человека против ИИ ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'c3-d4');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.3: C##DEV_USER сдается, чтобы начать новую игру
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.3: Сдаемся в игре с ИИ ---');
    C##CHECKERS_APP.game_logic.resign_game();
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.4: C##DEV_USER создает игру против ИИ (Сложность 1, играет за Черных)
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.4: Создание игры против ИИ (Сложность 1, Черные) ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 1,       -- << ИЗМЕНЕНО: Средняя сложность
        p_player_color  => 'B'       -- Играем за черных, ИИ ходит первым
    );
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.5: Ход человека против ИИ ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'f6-g5');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.6: Сдаемся в игре с ИИ ---');
    C##CHECKERS_APP.game_logic.resign_game();
END;
/

-- =================================================================
-- == ЭТАП 2: ИГРА МЕЖДУ ИГРОКАМИ (PvP)
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 2.1: C##DEV_USER создает открытую игру (open game)
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.1: Создание открытой PvP игры ---');
    C##CHECKERS_APP.game_logic.create_game(
         p_player_color  => 'W' -- Явно указываем цвет для предсказуемости
    );
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2.2: C##DEV2_USER присоединяется к открытой игре
-- >> ЭТОТ БЛОК НУЖНО ВЫПОЛНИТЬ В ОТДЕЛЬНОЙ СЕССИИ ПОД C##DEV2_USER <<
-- -----------------------------------------------------------------
DECLARE
    v_open_game_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.2: C##DEV2_USER ищет и присоединяется к игре ---');
    SELECT game_id INTO v_open_game_id FROM C##CHECKERS_APP.games WHERE status = 'O' AND ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE('[INFO] Найдена открытая игра ID: ' || v_open_game_id || '. Присоединяемся...');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_open_game_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Игра началась! Текущее состояние:');
    C##CHECKERS_APP.game_logic.print_board(p_game_id => v_open_game_id);
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('[ERROR] Открытых игр не найдено!');
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2.3: Игроки делают ходы (выполнять поочередно в своих сессиях)
-- >> СНАЧАЛА В СЕССИИ C##DEV_USER <<
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.3: Ход Белых (C##DEV_USER) ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'c3-d4');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- >> ТЕПЕРЬ В СЕССИИ C##DEV2_USER <<
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.3: Ход Черных (C##DEV2_USER) ---');
    C##CHECKERS_APP.game_logic.make_move(p_move_notation => 'h6-g5');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 2.4: Один из игроков сдается
-- >> В СЕССИИ C##DEV2_USER <<
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.4: C##DEV2_USER сдается ---');
    C##CHECKERS_APP.game_logic.resign_game();
END;
/

-- =================================================================
-- == ЭТАП 3: ЗАДАЧИ (PUZZLES) - ПРЕДОПРЕДЕЛЕННЫЕ И ЕЖЕДНЕВНЫЕ
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 3.1: Просмотр доступных задач
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.1: Просмотр всех серверных задач ---');
    C##CHECKERS_APP.game_logic.show_puzzles(); -- Show all
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Просмотр только легких (Difficulty 0) ---');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 0); -- Show only easy
END;
/

-- -----------------------------------------------------------------
-- ШАГ 3.2: Просмотр и запуск ежедневной задачи
-- (Manually ensure a daily puzzle exists for today first!)
-- E.g., INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (TRUNC(SYSDATE), (SELECT puzzle_id FROM puzzles WHERE created_by_player_id IS NULL ORDER BY dbms_random.value FETCH FIRST 1 ROW ONLY)); COMMIT;
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.2: Просмотр сегодняшней задачи ---');
    C##CHECKERS_APP.game_logic.show_daily_puzzle(); -- Show today's
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Запуск ежедневной задачи ---');
    C##CHECKERS_APP.game_logic.start_daily_puzzle();
EXCEPTION
    WHEN C##CHECKERS_APP.game_logic.e_daily_puzzle_missing THEN
         DBMS_OUTPUT.PUT_LINE('[INFO] Ежедневная задача на сегодня еще не назначена.');
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/




SET SERVEROUTPUT ON;
BEGIN
    C##CHECKERS_APP.game_logic.print_puzzle_board();
END;

- -----------------------------------------------------------------
-- ШАГ 3.3: Выход из текущей попытки решения задачи
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.3: Выход из попытки (если она была начата) ---');
    C##CHECKERS_APP.game_logic.quit_puzzle_attempt();
END;
/

-- -----------------------------------------------------------------
-- ШАГ 3.4: Решение задачи (сначала неправильный ход, потом правильный)
-- -----------------------------------------------------------------
DECLARE
    v_puzzle_id_to_solve NUMBER;
BEGIN
    -- Select the ID of the second server puzzle (assuming IDs might change)
    SELECT puzzle_id INTO v_puzzle_id_to_solve FROM (
        SELECT puzzle_id FROM puzzles WHERE created_by_player_id IS NULL ORDER BY puzzle_id
    ) WHERE ROWNUM = 2; -- Select the second one

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.4: Начинаем решать задачу ID '|| v_puzzle_id_to_solve ||' ---');
    C##CHECKERS_APP.game_logic.start_puzzle(p_puzzle_id => v_puzzle_id_to_solve);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Делаем правильный первый ход: f2-g3 (для Задачи 2) ---');
    C##CHECKERS_APP.game_logic.make_puzzle_move('f2-g3');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Делаем НЕПРАВИЛЬНЫЙ второй ход: c1-b2 ---');
    C##CHECKERS_APP.game_logic.make_puzzle_move('c1-b2'); -- This should fail the attempt

EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/
-- Verify the attempt status is 'F'
SELECT attempt_id, puzzle_id, status FROM puzzle_attempts WHERE player_id = (SELECT player_id FROM players WHERE username=USER) ORDER BY start_time DESC FETCH FIRST 1 ROW ONLY;

-- =================================================================
-- == ЭТАП 4: ЗАДАЧИ (PUZZLES) - ПОЛЬЗОВАТЕЛЬСКИЕ
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 4.1: Создание своей задачи
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.1: Создание пользовательской задачи ---');
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position   => '8w78b78888', -- Example RLE for 8x8
        p_turn_to_move     => 'W',
        p_moves_to_solve   => NULL, -- We made this nullable
        p_difficulty_level => 1
    );
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 4.2: Просмотр своих задач
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.2: Просмотр своих задач ---');
    C##CHECKERS_APP.game_logic.show_my_puzzles();
END;
/

-- -----------------------------------------------------------------
-- ШАГ 4.3: Запуск своей задачи (превращается в PvE игру)
-- -----------------------------------------------------------------
DECLARE
    v_my_puzzle_id NUMBER;
BEGIN
    SELECT puzzle_id INTO v_my_puzzle_id
    FROM puzzles
    WHERE created_by_player_id = (SELECT player_id FROM players WHERE username=USER)
    ORDER BY puzzle_id DESC FETCH FIRST 1 ROW ONLY; -- Get the latest one created

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.3: Запуск своей задачи ID '|| v_my_puzzle_id ||' как PvE игры ---');
    C##CHECKERS_APP.game_logic.start_puzzle(p_puzzle_id => v_my_puzzle_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 4.4: Сдаемся в этой PvE игре, чтобы очистить активную сессию
-- -----------------------------------------------------------------
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.4: Сдаемся в игре из пользовательской задачи ---');
    C##CHECKERS_APP.game_logic.resign_game();
END;
/
-- -----------------------------------------------------------------
-- ШАГ 4.5: Удаление своей задачи
-- -----------------------------------------------------------------
DECLARE
    v_my_puzzle_id NUMBER;
BEGIN
     SELECT puzzle_id INTO v_my_puzzle_id
    FROM puzzles
    WHERE created_by_player_id = (SELECT player_id FROM players WHERE username=USER)
    ORDER BY puzzle_id DESC FETCH FIRST 1 ROW ONLY; -- Get the latest one created

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.5: Удаление своей задачи ID '|| v_my_puzzle_id ||' ---');
    C##CHECKERS_APP.game_logic.delete_my_puzzle(p_puzzle_id => v_my_puzzle_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ОШИБКА] ' || SQLERRM);
END;
/


-- =================================================================
-- == ЭТАП 5: ПРОСМОТР ЗАПИСИ ПАРТИИ (REPLAY)
-- =================================================================
DECLARE
    v_game_to_watch NUMBER;
BEGIN
    SELECT game_id INTO v_game_to_watch FROM (
        SELECT game_id FROM C##CHECKERS_APP.games WHERE status NOT IN ('A', 'O', 'C') ORDER BY end_time DESC
    ) WHERE ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 5: Просмотр записи последней завершенной партии ID: ' || v_game_to_watch || ' ---');
    C##CHECKERS_APP.game_logic.start_replay_session(p_game_id => v_game_to_watch);
    
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Показываем все ходы ---');
    C##CHECKERS_APP.game_logic.show_next_replay_move(p_game_id => v_game_to_watch, p_moves_to_show => 20); -- Показать до 20 ходов
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/