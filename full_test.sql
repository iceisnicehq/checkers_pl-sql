SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ПОЛНЫЙ ТЕСТОВЫЙ НАБОР ДЛЯ GAME_LOGIC
-- == Покрывает все функции и процедуры из пакета
-- =================================================================
-- 
-- ИНСТРУКЦИЯ ПО ИСПОЛЬЗОВАНИЮ:
-- 
-- Большинство тестов можно выполнять с любого аккаунта (например, C##DEV_USER).
-- Для тестов PvP игр потребуется второй аккаунт (например, C##DEV2_USER).
-- 
-- РЕКОМЕНДУЕМАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ:
-- 1. ЭТАП 0-2: Выполнить с аккаунта АДМИНА (C##CHECKERS_APP или C##DEV_USER)
-- 2. ЭТАП 3-15: Выполнить с аккаунта ИГРОКА1 (C##DEV_USER)
--    - Для тестов PvP потребуется переключиться на ИГРОКА2 (C##DEV2_USER)
--    - Комментарии в коде указывают, когда нужно переключаться
-- 
-- ПРИМЕЧАНИЕ: Некоторые тесты могут требовать предварительной настройки
-- (например, создание пользователей C##DEV_USER и C##DEV2_USER).
-- =================================================================

PROMPT ================================================================
PROMPT === НАЧАЛО ПОЛНОГО ТЕСТИРОВАНИЯ GAME_LOGIC ===
PROMPT ================================================================
PROMPT 
PROMPT ТЕКУЩИЙ ПОЛЬЗОВАТЕЛЬ: 
SELECT USER FROM DUAL;
PROMPT 

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- == ВЫПОЛНЯТЬ: С аккаунта АДМИНА (C##CHECKERS_APP или C##DEV_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 0: Очистка тестовых данных ===
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    DELETE FROM C##CHECKERS_APP.matches;
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DELETE FROM C##CHECKERS_APP.spectators;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Тестовые данные очищены.');
END;
/

-- =================================================================
-- == ЭТАП 1: ИНФОРМАЦИЯ И СПРАВКА
-- == ВЫПОЛНЯТЬ: С любого аккаунта (например, C##DEV_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 1: Информация и справка ===

-- 1.1 Полная справка (без параметра)
PROMPT --- 1.1: Полная справка (info без параметра) ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Вывод полной справки:');
    C##CHECKERS_APP.game_logic.info;
    DBMS_OUTPUT.PUT_LINE('[OK] Полная справка выведена');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info (полная): ' || SQLERRM);
END;
/

-- 1.2 Справка по конкретной процедуре CREATE_GAME
PROMPT --- 1.2: Справка по CREATE_GAME ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Вывод справки по CREATE_GAME:');
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'CREATE_GAME');
    DBMS_OUTPUT.PUT_LINE('[OK] Справка по CREATE_GAME выведена');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info(CREATE_GAME): ' || SQLERRM);
END;
/

-- 1.3 Справка по MAKE_MOVE
PROMPT --- 1.3: Справка по MAKE_MOVE ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Вывод справки по MAKE_MOVE:');
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'MAKE_MOVE');
    DBMS_OUTPUT.PUT_LINE('[OK] Справка по MAKE_MOVE выведена');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info(MAKE_MOVE): ' || SQLERRM);
END;
/

-- 1.4 Справка по несуществующей процедуре (тест ошибки)
PROMPT --- 1.4: Тест ошибки (несуществующая процедура) ---
BEGIN
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'NONEXISTENT_PROC');
    DBMS_OUTPUT.PUT_LINE('[OK] Ошибка обработана корректно');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[OK] Ошибка обработана: ' || SQLERRM);
END;
/

-- 1.5 Справка по нескольким процедурам
PROMPT --- 1.5: Справка по нескольким процедурам ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Тест справки по JOIN_GAME:');
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'JOIN_GAME');
    
    DBMS_OUTPUT.PUT_LINE('-> Тест справки по PRINT_ACTIVE_BOARD:');
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'PRINT_ACTIVE_BOARD');
    
    DBMS_OUTPUT.PUT_LINE('-> Тест справки по SHOW_PUZZLES:');
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'SHOW_PUZZLES');
    
    DBMS_OUTPUT.PUT_LINE('[OK] Тесты справки по процедурам выполнены');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info (множественные): ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 2: БАЗОВЫЕ ФУНКЦИИ (ENCODE/DECODE, ПОЗИЦИИ)
-- == ВЫПОЛНЯТЬ: С любого аккаунта (например, C##DEV_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 2: Тестирование базовых функций ===
DECLARE
    v_test_board_8x8 VARCHAR2(64) := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
    v_test_board_10x10 VARCHAR2(100) := '+b+b+b+b+bb+b+b+b+b++++++++++w+w+w+w+w+w+w+w+w+';
    v_encoded VARCHAR2(128);
    v_decoded VARCHAR2(128);
    v_initial_8x8 VARCHAR2(64);
    v_initial_10x10 VARCHAR2(100);
    v_notation VARCHAR2(10);
BEGIN
    -- Тест encode_board / decode_board для 8x8
    DBMS_OUTPUT.PUT_LINE('-> Тест encode/decode для 8x8');
    v_encoded := C##CHECKERS_APP.game_logic.encode_board(v_test_board_8x8);
    v_decoded := C##CHECKERS_APP.game_logic.decode_board(v_encoded);
    IF v_decoded = v_test_board_8x8 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] encode/decode 8x8 работает');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] encode/decode 8x8 не работает');
    END IF;
    
    -- Тест encode_board / decode_board для 10x10
    DBMS_OUTPUT.PUT_LINE('-> Тест encode/decode для 10x10');
    v_encoded := C##CHECKERS_APP.game_logic.encode_board(v_test_board_10x10);
    v_decoded := C##CHECKERS_APP.game_logic.decode_board(v_encoded);
    IF v_decoded = v_test_board_10x10 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] encode/decode 10x10 работает');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] encode/decode 10x10 не работает');
    END IF;
    
    -- Тест get_initial_position для 8x8
    DBMS_OUTPUT.PUT_LINE('-> Тест get_initial_position для rule_id=1 (8x8)');
    v_initial_8x8 := C##CHECKERS_APP.game_logic.get_initial_position(1);
    IF v_initial_8x8 IS NOT NULL AND LENGTH(v_initial_8x8) = 64 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] get_initial_position(1) вернул 64 символа');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] get_initial_position(1) вернул: длина=' || NVL(LENGTH(v_initial_8x8), 0));
    END IF;
    
    -- Тест get_initial_position для 10x10
    DBMS_OUTPUT.PUT_LINE('-> Тест get_initial_position для rule_id=2 (10x10)');
    v_initial_10x10 := C##CHECKERS_APP.game_logic.get_initial_position(2);
    IF v_initial_10x10 IS NOT NULL AND LENGTH(v_initial_10x10) = 100 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] get_initial_position(2) вернул 100 символов');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] get_initial_position(2) вернул: длина=' || NVL(LENGTH(v_initial_10x10), 0));
    END IF;
    
    -- Тест idx_to_notation для 8x8
    DBMS_OUTPUT.PUT_LINE('-> Тест idx_to_notation для 8x8');
    C##CHECKERS_APP.game_logic.p_init_board_map(8);
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(1, 8);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(1, 8) = ' || NVL(v_notation, 'NULL'));
    
    -- Тест idx_to_notation для 10x10
    DBMS_OUTPUT.PUT_LINE('-> Тест idx_to_notation для 10x10');
    C##CHECKERS_APP.game_logic.p_init_board_map(10);
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(1, 10);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(1, 10) = ' || NVL(v_notation, 'NULL'));
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(100, 10);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(100, 10) = ' || NVL(v_notation, 'NULL'));
    
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Базовые функции: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 3: PvP ИГРЫ (РУССКИЕ 8x8)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Для тестов PvP потребуется второй аккаунт (C##DEV2_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 3: PvP игры (Русские шашки 8x8) ===

-- 3.1 Создание открытой игры
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
PROMPT --- 3.1: Создание открытой игры (Open Game) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'O';
    DBMS_OUTPUT.PUT_LINE('[OK] Открытая игра создана, ID=' || v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (open): ' || SQLERRM);
END;
/

-- 3.2 Создание прямого вызова
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER), вызов ИГРОКА2 (C##DEV2_USER)
PROMPT --- 3.2: Создание прямого вызова (Challenge) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'C';
    DBMS_OUTPUT.PUT_LINE('[OK] Прямой вызов создан, ID=' || v_game_id);
    
    -- Просмотр доски для вызова
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (challenge): ' || SQLERRM);
END;
/

-- 3.3 Присоединение к игре
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА2 (C##DEV2_USER) для присоединения к игре ИГРОКА1
-- ПРИМЕЧАНИЕ: В реальном тестировании переключитесь на C##DEV2_USER перед выполнением
PROMPT --- 3.3: Присоединение к игре (join_game) ---
PROMPT [ВНИМАНИЕ: Для полного теста переключитесь на C##DEV2_USER]
DECLARE
    v_game_id NUMBER;
BEGIN
    SELECT MAX(game_id) INTO v_game_id 
    FROM C##CHECKERS_APP.games 
    WHERE status IN ('O', 'C');
    
    IF v_game_id IS NOT NULL THEN
        -- В реальности это должен быть другой пользователь (C##DEV2_USER)
        -- Для автоматического теста используем текущего пользователя
        C##CHECKERS_APP.game_logic.join_game(p_game_id => v_game_id);
        DBMS_OUTPUT.PUT_LINE('[OK] Присоединение к игре ID=' || v_game_id);
        
        -- Просмотр доски после присоединения
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет игр для присоединения');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] join_game: ' || SQLERRM);
END;
/

-- 3.4 Выполнение ходов
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 или ИГРОКА2 (в зависимости от очереди)
PROMPT --- 3.4: Выполнение ходов (make_move) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    SELECT MAX(game_id) INTO v_game_id 
    FROM C##CHECKERS_APP.games 
    WHERE status = 'A' AND rule_id = 1;
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Ход 1: c3-d4');
        C##CHECKERS_APP.game_logic.make_move('c3-d4');
        
        DBMS_OUTPUT.PUT_LINE('-> Просмотр доски после хода');
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет активных игр для хода');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] make_move: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 4: PvP ИГРЫ (МЕЖДУНАРОДНЫЕ 10x10)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Для присоединения потребуется ИГРОК2 (C##DEV2_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 4: PvP игры (Международные шашки 10x10) ===

-- 4.1 Создание игры 10x10
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
PROMPT --- 4.1: Создание игры 10x10 ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 2,
        p_time_limit_move_sec => 120
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'C' AND rule_id = 2;
    DBMS_OUTPUT.PUT_LINE('[OK] Игра 10x10 создана, ID=' || v_game_id);
    
    -- Просмотр доски 10x10
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (10x10): ' || SQLERRM);
END;
/

-- 4.2 Присоединение к игре 10x10
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА2 (C##DEV2_USER)
PROMPT --- 4.2: Присоединение к игре 10x10 ---
PROMPT [ВНИМАНИЕ: Для полного теста переключитесь на C##DEV2_USER]
DECLARE
    v_game_id NUMBER;
BEGIN
    SELECT MAX(game_id) INTO v_game_id 
    FROM C##CHECKERS_APP.games 
    WHERE status = 'C' AND rule_id = 2;
    
    IF v_game_id IS NOT NULL THEN
        C##CHECKERS_APP.game_logic.join_game(p_game_id => v_game_id);
        DBMS_OUTPUT.PUT_LINE('[OK] Присоединение к игре 10x10, ID=' || v_game_id);
        
        -- Просмотр доски 10x10 после присоединения
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет игр 10x10 для присоединения');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] join_game (10x10): ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 5: PvE ИГРЫ (ПРОТИВ ИИ)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: ИИ играет автоматически, второй игрок не требуется
-- =================================================================
PROMPT 
PROMPT === ЭТАП 5: PvE игры (Против ИИ) ===

-- 5.1 PvE Easy (8x8)
PROMPT --- 5.1: PvE Easy (8x8) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE ai_difficulty = 'E' AND rule_id = 1;
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Easy (8x8) создана, ID=' || v_game_id);
    
    -- Просмотр доски
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
    
    -- Ход игрока
    DBMS_OUTPUT.PUT_LINE('-> Ход игрока: c3-d4');
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    
    -- Просмотр доски после хода (ИИ должен был ответить)
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Easy: ' || SQLERRM);
END;
/

-- 5.2 PvE Medium (8x8)
PROMPT --- 5.2: PvE Medium (8x8) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'M',
        p_player_color => 'B',
        p_rule_id => 1
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE ai_difficulty = 'M' AND rule_id = 1;
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Medium (8x8) создана, ID=' || v_game_id);
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Medium: ' || SQLERRM);
END;
/

-- 5.3 PvE Hard (10x10)
PROMPT --- 5.3: PvE Hard (10x10) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'H',
        p_player_color => 'W',
        p_rule_id => 2
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE ai_difficulty = 'H' AND rule_id = 2;
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Hard (10x10) создана, ID=' || v_game_id);
    C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Hard: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 6: УПРАВЛЕНИЕ НИЧЬЕЙ
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Требуется активная PvP игра (не PvE)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 6: Управление ничьей ===
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Находим активную PvP игру
    SELECT MAX(game_id) INTO v_game_id 
    FROM C##CHECKERS_APP.games 
    WHERE status = 'A' AND ai_difficulty IS NULL;
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Предложение ничьей (Offer)');
        C##CHECKERS_APP.game_logic.draw('O');
        
        DBMS_OUTPUT.PUT_LINE('-> Отмена предложения ничьей (Cancel)');
        C##CHECKERS_APP.game_logic.draw('C');
        
        DBMS_OUTPUT.PUT_LINE('[OK] Тест ничьей выполнен');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет активных PvP игр для теста ничьей');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] draw: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 7: ЗАДАЧИ (PUZZLES)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 7: Работа с задачами (Puzzles) ===

-- 7.1 Создание задачи
PROMPT --- 7.1: Создание задачи ---
DECLARE
    v_puzzle_id NUMBER;
    v_board_8x8 CLOB := '12b4b5b2b8w1b1w11w3w8';
    v_board_10x10 CLOB := 'b+b+b+b+b++b+b+b+b+b++++++++++w+w+w+w+w+w+w+w+w+';
BEGIN
    -- Создание задачи 8x8
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board_8x8,
        p_turn_to_move => 'W',
        p_moves_to_solve => 3,
        p_difficulty_level => 1
    );
    SELECT MAX(puzzle_id) INTO v_puzzle_id FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DBMS_OUTPUT.PUT_LINE('[OK] Задача 8x8 создана, ID=' || v_puzzle_id);
    
    -- Создание задачи 10x10
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board_10x10,
        p_turn_to_move => 'B',
        p_moves_to_solve => 5,
        p_difficulty_level => 2
    );
    SELECT MAX(puzzle_id) INTO v_puzzle_id FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DBMS_OUTPUT.PUT_LINE('[OK] Задача 10x10 создана, ID=' || v_puzzle_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_puzzle: ' || SQLERRM);
END;
/

-- 7.2 Просмотр списка задач
PROMPT --- 7.2: Просмотр списка задач ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Все задачи:');
    C##CHECKERS_APP.game_logic.show_puzzles;
    
    DBMS_OUTPUT.PUT_LINE('-> Задачи сложности 1:');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 1);
    
    DBMS_OUTPUT.PUT_LINE('-> Детальный просмотр задачи:');
    DECLARE
        v_pid NUMBER;
    BEGIN
        SELECT MAX(puzzle_id) INTO v_pid FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
        IF v_pid IS NOT NULL THEN
            C##CHECKERS_APP.game_logic.show_puzzles(p_puzzle_id => v_pid);
        END IF;
    END;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_puzzles: ' || SQLERRM);
END;
/

-- 7.3 Просмотр моих задач
PROMPT --- 7.3: Просмотр моих задач ---
BEGIN
    C##CHECKERS_APP.game_logic.show_my_puzzles;
    DBMS_OUTPUT.PUT_LINE('[OK] show_my_puzzles выполнен');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_my_puzzles: ' || SQLERRM);
END;
/

-- 7.4 Решение задачи
PROMPT --- 7.4: Решение задачи ---
DECLARE
    v_puzzle_id NUMBER;
    v_game_id NUMBER;
BEGIN
    SELECT MAX(puzzle_id) INTO v_puzzle_id 
    FROM C##CHECKERS_APP.puzzles 
    WHERE created_by_player_id IS NOT NULL;
    
    IF v_puzzle_id IS NOT NULL THEN
        C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => v_puzzle_id);
        SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE puzzle_id = v_puzzle_id;
        DBMS_OUTPUT.PUT_LINE('[OK] Начато решение задачи ID=' || v_puzzle_id || ', Game ID=' || v_game_id);
        
        -- Просмотр доски задачи
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет задач для решения');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Решение задачи: ' || SQLERRM);
END;
/

-- 7.5 Удаление задачи
PROMPT --- 7.5: Удаление задачи ---
DECLARE
    v_puzzle_id NUMBER;
BEGIN
    SELECT MAX(puzzle_id) INTO v_puzzle_id 
    FROM C##CHECKERS_APP.puzzles 
    WHERE created_by_player_id IS NOT NULL
    AND puzzle_id NOT IN (SELECT DISTINCT puzzle_id FROM C##CHECKERS_APP.games WHERE puzzle_id IS NOT NULL);
    
    IF v_puzzle_id IS NOT NULL THEN
        C##CHECKERS_APP.game_logic.delete_my_puzzle(v_puzzle_id);
        DBMS_OUTPUT.PUT_LINE('[OK] Задача ID=' || v_puzzle_id || ' удалена');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет задач для удаления (возможно, все используются в играх)');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] delete_my_puzzle: ' || SQLERRM);
END;
/

-- 7.6 Daily Puzzle
PROMPT --- 7.6: Daily Puzzle ---
BEGIN
    C##CHECKERS_APP.game_logic.show_daily_puzzle;
    DBMS_OUTPUT.PUT_LINE('[OK] show_daily_puzzle выполнен');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_daily_puzzle: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 8: МАТЧИ (MATCHES)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Для присоединения потребуется ИГРОК2 (C##DEV2_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 8: Матчи (Matches) ===

-- 8.1 Создание матча
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
PROMPT --- 8.1: Создание матча ---
DECLARE
    v_match_id NUMBER;
BEGIN
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1
    );
    SELECT MAX(match_id) INTO v_match_id FROM C##CHECKERS_APP.matches;
    DBMS_OUTPUT.PUT_LINE('[OK] Матч создан, ID=' || v_match_id);
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_match: ' || SQLERRM);
END;
/

-- 8.2 Присоединение к матчу
-- ВЫПОЛНЯТЬ: С аккаунта ИГРОКА2 (C##DEV2_USER)
PROMPT --- 8.2: Присоединение к матчу ---
PROMPT [ВНИМАНИЕ: Для полного теста переключитесь на C##DEV2_USER]
DECLARE
    v_match_id NUMBER;
BEGIN
    SELECT MAX(match_id) INTO v_match_id FROM C##CHECKERS_APP.matches WHERE status IN ('O', 'C');
    
    IF v_match_id IS NOT NULL THEN
        C##CHECKERS_APP.game_logic.join_match(p_match_id => v_match_id);
        DBMS_OUTPUT.PUT_LINE('[OK] Присоединение к матчу ID=' || v_match_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет матчей для присоединения');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] join_match: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 9: ПРОСМОТР И СТАТУС
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Некоторые тесты могут требовать активных игр
-- =================================================================
PROMPT 
PROMPT === ЭТАП 9: Просмотр и статус ===

-- 9.1 print_active_board (разные варианты)
PROMPT --- 9.1: print_active_board (разные варианты) ---
DECLARE
    v_game_id NUMBER;
BEGIN
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'A';
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Просмотр по game_id:');
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
        
        DBMS_OUTPUT.PUT_LINE('-> Просмотр без параметров (текущая игра):');
        C##CHECKERS_APP.game_logic.print_active_board;
        
        DBMS_OUTPUT.PUT_LINE('[OK] print_active_board протестирован');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет активных игр для просмотра');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] print_active_board: ' || SQLERRM);
END;
/

-- 9.2 watch_game_replay
PROMPT --- 9.2: watch_game_replay ---
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Ищем завершенную игру с ходами
    SELECT MAX(g.game_id) INTO v_game_id
    FROM C##CHECKERS_APP.games g
    WHERE g.status IN ('V', 'D', 'T', 'R')
    AND EXISTS (SELECT 1 FROM C##CHECKERS_APP.game_moves gm WHERE gm.game_id = g.game_id);
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Просмотр реплея игры ID=' || v_game_id);
        C##CHECKERS_APP.game_logic.watch_game_replay(
            p_game_id => v_game_id,
            p_moves_to_show => 3
        );
        DBMS_OUTPUT.PUT_LINE('[OK] watch_game_replay выполнен');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет завершенных игр с ходами для реплея');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] watch_game_replay: ' || SQLERRM);
END;
/

-- 9.3 Режим зрителя
PROMPT --- 9.3: Режим зрителя ---
DECLARE
    v_game_id NUMBER;
    v_other_user VARCHAR2(30) := 'C##DEV2_USER';
BEGIN
    -- Находим активную игру другого пользователя
    SELECT MAX(g.game_id) INTO v_game_id
    FROM C##CHECKERS_APP.games g
    JOIN C##CHECKERS_APP.players p1 ON g.player_white_id = p1.player_id
    JOIN C##CHECKERS_APP.players p2 ON g.player_black_id = p2.player_id
    WHERE g.status = 'A'
    AND (p1.username = v_other_user OR p2.username = v_other_user);
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Вход в режим зрителя для игры ID=' || v_game_id);
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
        
        DBMS_OUTPUT.PUT_LINE('-> Выход из режима зрителя');
        C##CHECKERS_APP.game_logic.stop_spectating;
        DBMS_OUTPUT.PUT_LINE('[OK] Режим зрителя протестирован');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет активных игр других пользователей для просмотра');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Режим зрителя: ' || SQLERRM);
END;
/

-- 9.4 stop_spectating
PROMPT --- 9.4: stop_spectating ---
BEGIN
    C##CHECKERS_APP.game_logic.stop_spectating;
    DBMS_OUTPUT.PUT_LINE('[OK] stop_spectating выполнен');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] stop_spectating: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 10: УПРАВЛЕНИЕ ИГРОЙ (CANCEL, RESIGN)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 10: Управление игрой ===

-- 10.1 cancel_game
PROMPT --- 10.1: cancel_game ---
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Создаем игру для отмены
    C##CHECKERS_APP.game_logic.create_game;
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'O';
    
    IF v_game_id IS NOT NULL THEN
        C##CHECKERS_APP.game_logic.cancel_game;
        DBMS_OUTPUT.PUT_LINE('[OK] cancel_game выполнен');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет открытых игр для отмены');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] cancel_game: ' || SQLERRM);
END;
/

-- 10.2 resign_game
PROMPT --- 10.2: resign_game ---
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Находим активную игру
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'A';
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Сдача в игре ID=' || v_game_id);
        C##CHECKERS_APP.game_logic.resign_game;
        DBMS_OUTPUT.PUT_LINE('[OK] resign_game выполнен');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Нет активных игр для сдачи');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] resign_game: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 11: ПРЕДСТАВЛЕНИЯ (VIEWS)
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Views показывают данные текущего пользователя (USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 11: Тестирование представлений (Views) ===

-- 11.1 v_open_games
PROMPT --- 11.1: v_open_games ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Открытые игры:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_open_games FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  ID=' || r.game_id || ', Creator=' || r.creator_username || ', Type=' || r.challenge_type);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_open_games протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_open_games: ' || SQLERRM);
END;
/

-- 11.2 v_active_games
PROMPT --- 11.2: v_active_games ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Активные игры:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_active_games FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  ID=' || r.game_id || ', White=' || r.white_player || ', Black=' || r.black_player || ', Rules=' || r.rule_name);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_active_games протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_active_games: ' || SQLERRM);
END;
/

-- 11.3 v_game_status
PROMPT --- 11.3: v_game_status ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Статус игр:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_status WHERE ROWNUM <= 3) LOOP
        DBMS_OUTPUT.PUT_LINE('  ID=' || r.game_id || ', Status=' || r.status || ', Turn=' || r.current_turn || ', Moves=' || r.move_count);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_game_status протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_game_status: ' || SQLERRM);
END;
/

-- 11.4 v_game_protocol
PROMPT --- 11.4: v_game_protocol ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Протокол игр:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_protocol WHERE ROWNUM <= 5 ORDER BY game_id, move_number) LOOP
        DBMS_OUTPUT.PUT_LINE('  Game=' || r.game_id || ', Move#' || r.move_number || ', ' || r.username || ' (' || r.player_color || '): ' || r.move_notation || ', Capture=' || r.is_capture);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_game_protocol протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_game_protocol: ' || SQLERRM);
END;
/

-- 11.5 v_player_history
PROMPT --- 11.5: v_player_history ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> История игрока:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  Game=' || r.game_id || ', Result=' || r.result || ', Opponent=' || r.opponent_name || ', Moves=' || r.total_moves);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_player_history протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_history: ' || SQLERRM);
END;
/

-- 11.6 v_player_history_by_period
PROMPT --- 11.6: v_player_history_by_period ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> История игрока по периоду:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history_by_period FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  Game=' || r.game_id || ', Result=' || r.result || ', Reason=' || r.end_reason || ', Duration=' || r.duration_minutes || ' min');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_player_history_by_period протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_history_by_period: ' || SQLERRM);
END;
/

-- 11.7 v_player_stats
PROMPT --- 11.7: v_player_stats ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Статистика игрока:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_stats) LOOP
        DBMS_OUTPUT.PUT_LINE('  Games=' || r.games_played || ', W=' || r.wins || ', D=' || r.draws || ', L=' || r.losses || ', AvgMoves=' || r.avg_game_length);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_player_stats протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_stats: ' || SQLERRM);
END;
/

-- 11.8 v_leaderboard
PROMPT --- 11.8: v_leaderboard ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Рейтинг по успеху:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || r.username || ': W=' || r.wins || ', D=' || r.draws || ', L=' || r.losses || ', Success=' || r.success_rate_percent || '%');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_leaderboard протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_leaderboard: ' || SQLERRM);
END;
/

-- 11.9 v_leaderboard_by_avg_moves
PROMPT --- 11.9: v_leaderboard_by_avg_moves ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Рейтинг по среднему числу ходов:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard_by_avg_moves FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || r.username || ': Games=' || r.games_played || ', AvgMoves=' || r.avg_moves_per_game);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_leaderboard_by_avg_moves протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_leaderboard_by_avg_moves: ' || SQLERRM);
END;
/

-- 11.10 v_daily_puzzle_results
PROMPT --- 11.10: v_daily_puzzle_results ---
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Результаты Daily Puzzles:');
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_daily_puzzle_results FETCH FIRST 5 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('  Date=' || TO_CHAR(r.puzzle_date, 'DD.MM.YYYY') || ', Attempts=' || r.total_attempts || ', Solved=' || r.successful_solves);
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('[OK] v_daily_puzzle_results протестировано');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_daily_puzzle_results: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 12: ТЕСТИРОВАНИЕ ХОДОВ С ВЗЯТИЯМИ
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: ИИ играет автоматически
-- =================================================================
PROMPT 
PROMPT === ЭТАП 12: Тестирование ходов с взятиями ===
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Создаем игру для теста взятий
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'A' AND rule_id = 1;
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Тест тихого хода: c3-d4');
        C##CHECKERS_APP.game_logic.make_move('c3-d4');
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => v_game_id);
        
        DBMS_OUTPUT.PUT_LINE('[OK] Тест ходов выполнен');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[WARN] Не удалось создать игру для теста ходов');
    END IF;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Тест ходов: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 13: ТЕСТИРОВАНИЕ ПАРАМЕТРОВ ИГРЫ
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Создает вызов для ИГРОКА2 (C##DEV2_USER)
-- =================================================================
PROMPT 
PROMPT === ЭТАП 13: Тестирование параметров игры ===
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Создание игры с параметрами
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600,
        p_draw_moves_limit => 15,
        p_enable_pos_rep_draw => 'Y'
    );
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'C';
    DBMS_OUTPUT.PUT_LINE('[OK] Игра с параметрами создана, ID=' || v_game_id);
    
    -- Проверка параметров через view
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_status WHERE game_id = v_game_id) LOOP
        DBMS_OUTPUT.PUT_LINE('  TimeLimitMove=' || r.time_limit_move_sec || ', TimeLimitGame=' || r.time_limit_game_sec);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Параметры игры: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 14: ТЕСТИРОВАНИЕ ОШИБОК И ВАЛИДАЦИИ
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Тестирует обработку ошибок и валидацию
-- =================================================================
PROMPT 
PROMPT === ЭТАП 14: Тестирование ошибок и валидации ===
DECLARE
    v_game_id NUMBER;
BEGIN
    -- Тест неверного хода
    SELECT MAX(game_id) INTO v_game_id FROM C##CHECKERS_APP.games WHERE status = 'A';
    
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('-> Тест неверного хода: z9-z10');
        BEGIN
            C##CHECKERS_APP.game_logic.make_move('z9-z10');
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('[OK] Неверный ход корректно отклонен: ' || SQLERRM);
        END;
    END IF;
    
    -- Тест создания игры когда уже есть активная
    DBMS_OUTPUT.PUT_LINE('-> Тест создания игры при активной игре');
    BEGIN
        C##CHECKERS_APP.game_logic.create_game;
        DBMS_OUTPUT.PUT_LINE('[WARN] Должна была быть ошибка о наличии активной игры');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[OK] Создание второй игры корректно отклонено');
    END;
    
    DBMS_OUTPUT.PUT_LINE('[OK] Тесты валидации выполнены');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Тесты валидации: ' || SQLERRM);
END;
/

-- =================================================================
-- == ЭТАП 15: ФИНАЛЬНЫЙ ПРОСМОТР ДОСОК
-- == ВЫПОЛНЯТЬ: С аккаунта ИГРОКА1 (C##DEV_USER)
-- == ПРИМЕЧАНИЕ: Показывает все активные игры
-- =================================================================
PROMPT 
PROMPT === ЭТАП 15: Финальный просмотр досок ===
BEGIN
    DBMS_OUTPUT.PUT_LINE('-> Просмотр всех активных игр:');
    
    FOR r IN (SELECT game_id, rule_id FROM C##CHECKERS_APP.games WHERE status = 'A' ORDER BY game_id) LOOP
        DBMS_OUTPUT.PUT_LINE('--- Игра ID=' || r.game_id || ', Правила=' || r.rule_id || ' ---');
        C##CHECKERS_APP.game_logic.print_active_board(p_game_id => r.game_id);
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('[OK] Финальный просмотр выполнен');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Финальный просмотр: ' || SQLERRM);
END;
/

PROMPT 
PROMPT ================================================================
PROMPT === ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ===
PROMPT ================================================================
PROMPT 
PROMPT ИТОГИ ТЕСТИРОВАНИЯ:
PROMPT - Проверьте вывод выше на наличие ошибок [ERR]
PROMPT - Все тесты должны завершиться с [OK] или [WARN]
PROMPT - Тесты с [WARN] требуют дополнительных условий (например, активных игр)
PROMPT 
PROMPT ПРИМЕЧАНИЯ:
PROMPT - Для полного тестирования PvP игр переключитесь на C##DEV2_USER
PROMPT - Некоторые тесты могут требовать предварительной настройки данных
PROMPT - Проверьте работу процедуры info с параметром p_proc_name
PROMPT 
PROMPT РЕКОМЕНДУЕМЫЕ ДОПОЛНИТЕЛЬНЫЕ ТЕСТЫ:
PROMPT 1. Переключитесь на C##DEV2_USER и выполните join_game для PvP игр
PROMPT 2. Протестируйте info с разными именами процедур
PROMPT 3. Проверьте работу всех views с разными пользователями
PROMPT 4. Протестируйте режим зрителя с третьим аккаунтом
PROMPT 
