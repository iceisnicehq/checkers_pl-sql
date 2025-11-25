SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- Полный тестовый набор для game_logic
-- Использует только процедуры пакета, без прямых SELECT из служебных таблиц

-- ЭТАП 0: Очистка (выполнять с аккаунта админа)
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    DELETE FROM C##CHECKERS_APP.matches;
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DELETE FROM C##CHECKERS_APP.spectators;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Очистка завершена');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Очистка: ' || SQLERRM);
END;
/

-- ЭТАП 1: Информация
BEGIN
    C##CHECKERS_APP.game_logic.info;
    DBMS_OUTPUT.PUT_LINE('[OK] Полная справка');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'CREATE_GAME');
    DBMS_OUTPUT.PUT_LINE('[OK] Справка по CREATE_GAME');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] info(CREATE_GAME): ' || SQLERRM);
END;
/

-- ЭТАП 2: Базовые функции
DECLARE
    v_test_8x8 VARCHAR2(64) := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
    v_test_10x10 VARCHAR2(100) := '+b+b+b+b+bb+b+b+b+b++++++++++w+w+w+w+w+w+w+w+w+';
    v_encoded VARCHAR2(128);
    v_decoded VARCHAR2(128);
    v_initial VARCHAR2(128);
    v_notation VARCHAR2(10);
BEGIN
    v_encoded := C##CHECKERS_APP.game_logic.encode_board(v_test_8x8);
    v_decoded := C##CHECKERS_APP.game_logic.decode_board(v_encoded);
    IF v_decoded = v_test_8x8 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] encode/decode 8x8');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] encode/decode 8x8');
    END IF;
    
    v_encoded := C##CHECKERS_APP.game_logic.encode_board(v_test_10x10);
    v_decoded := C##CHECKERS_APP.game_logic.decode_board(v_encoded);
    IF v_decoded = v_test_10x10 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] encode/decode 10x10');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] encode/decode 10x10');
    END IF;
    
    v_initial := C##CHECKERS_APP.game_logic.get_initial_position(1);
    IF v_initial IS NOT NULL AND LENGTH(v_initial) = 64 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] get_initial_position(1) = 64');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] get_initial_position(1)');
    END IF;
    
    v_initial := C##CHECKERS_APP.game_logic.get_initial_position(2);
    IF v_initial IS NOT NULL AND LENGTH(v_initial) = 100 THEN
        DBMS_OUTPUT.PUT_LINE('[OK] get_initial_position(2) = 100');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERR] get_initial_position(2)');
    END IF;
    
    C##CHECKERS_APP.game_logic.p_init_board_map(8);
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(1, 8);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(1,8) = ' || NVL(v_notation, 'NULL'));
    
    C##CHECKERS_APP.game_logic.p_init_board_map(10);
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(1, 10);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(1,10) = ' || NVL(v_notation, 'NULL'));
    v_notation := C##CHECKERS_APP.game_logic.idx_to_notation(100, 10);
    DBMS_OUTPUT.PUT_LINE('[OK] idx_to_notation(100,10) = ' || NVL(v_notation, 'NULL'));
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Базовые функции: ' || SQLERRM);
END;
/

-- ЭТАП 3: PvP игры 8x8
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Открытая игра 8x8 создана');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (open 8x8): ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Вызов 8x8 создан');
    C##CHECKERS_APP.game_logic.print_active_board;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (challenge 8x8): ' || SQLERRM);
END;
/

-- ЭТАП 4: PvP игры 10x10
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 2,
        p_time_limit_move_sec => 120
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Вызов 10x10 создан');
    C##CHECKERS_APP.game_logic.print_active_board;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_game (challenge 10x10): ' || SQLERRM);
END;
/

-- ЭТАП 5: PvE игры
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Easy 8x8 создана');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Easy: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'M',
        p_player_color => 'B',
        p_rule_id => 1
    );
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Medium 8x8 создана');
    C##CHECKERS_APP.game_logic.print_active_board;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Medium: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'H',
        p_player_color => 'W',
        p_rule_id => 2
    );
    DBMS_OUTPUT.PUT_LINE('[OK] PvE Hard 10x10 создана');
    C##CHECKERS_APP.game_logic.print_active_board;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] PvE Hard: ' || SQLERRM);
END;
/

-- ЭТАП 6: Управление ничьей
BEGIN
    C##CHECKERS_APP.game_logic.draw('O');
    DBMS_OUTPUT.PUT_LINE('[OK] Предложение ничьей');
    C##CHECKERS_APP.game_logic.draw('C');
    DBMS_OUTPUT.PUT_LINE('[OK] Отмена ничьей');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] draw: ' || SQLERRM);
END;
/

-- ЭТАП 7: Задачи (Puzzles)
DECLARE
    v_board_8x8 CLOB := '12b4b5b2b8w1b1w11w3w8';
    v_board_10x10 CLOB := 'b+b+b+b+b++b+b+b+b+b++++++++++w+w+w+w+w+w+w+w+w+';
BEGIN
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board_8x8,
        p_turn_to_move => 'W',
        p_moves_to_solve => 3,
        p_difficulty_level => 1
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Задача 8x8 создана');
    
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board_10x10,
        p_turn_to_move => 'B',
        p_moves_to_solve => 5,
        p_difficulty_level => 2
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Задача 10x10 создана');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_puzzle: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_puzzles;
    DBMS_OUTPUT.PUT_LINE('[OK] show_puzzles (все)');
    
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 1);
    DBMS_OUTPUT.PUT_LINE('[OK] show_puzzles (difficulty=1)');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_puzzles: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_my_puzzles;
    DBMS_OUTPUT.PUT_LINE('[OK] show_my_puzzles');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_my_puzzles: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_daily_puzzle;
    DBMS_OUTPUT.PUT_LINE('[OK] show_daily_puzzle');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] show_daily_puzzle: ' || SQLERRM);
END;
/

-- ЭТАП 8: Матчи
BEGIN
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Матч создан');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] create_match: ' || SQLERRM);
END;
/

-- ЭТАП 9: Просмотр и статус
BEGIN
    C##CHECKERS_APP.game_logic.print_active_board;
    DBMS_OUTPUT.PUT_LINE('[OK] print_active_board (текущая)');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] print_active_board: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.print_active_board(p_wait_for_turn => 'Y');
    DBMS_OUTPUT.PUT_LINE('[OK] print_active_board (с ожиданием)');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] print_active_board (wait): ' || SQLERRM);
END;
/

-- ЭТАП 10: Управление игрой
BEGIN
    C##CHECKERS_APP.game_logic.create_game;
    C##CHECKERS_APP.game_logic.cancel_game;
    DBMS_OUTPUT.PUT_LINE('[OK] cancel_game');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] cancel_game: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.resign_game;
    DBMS_OUTPUT.PUT_LINE('[OK] resign_game');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] resign_game: ' || SQLERRM);
END;
/

-- ЭТАП 11: Представления (Views)
BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_open_games FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_open_games: ID=' || r.game_id);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_open_games: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_active_games FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_active_games: ID=' || r.game_id);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_active_games: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_status WHERE ROWNUM <= 3) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_game_status: ID=' || r.game_id || ', Status=' || r.status);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_game_status: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_protocol WHERE ROWNUM <= 5 ORDER BY game_id, move_number) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_game_protocol: Game=' || r.game_id || ', Move=' || r.move_number);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_game_protocol: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_player_history: Game=' || r.game_id || ', Result=' || r.result);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_history: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history_by_period FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_player_history_by_period: Game=' || r.game_id);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_history_by_period: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_stats) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_player_stats: Games=' || r.games_played);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_player_stats: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_leaderboard: ' || r.username || ', Success=' || r.success_rate_percent);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_leaderboard: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard_by_avg_moves FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_leaderboard_by_avg_moves: ' || r.username);
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_leaderboard_by_avg_moves: ' || SQLERRM);
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_daily_puzzle_results FETCH FIRST 3 ROWS ONLY) LOOP
        DBMS_OUTPUT.PUT_LINE('[OK] v_daily_puzzle_results: Date=' || TO_CHAR(r.puzzle_date, 'DD.MM.YYYY'));
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] v_daily_puzzle_results: ' || SQLERRM);
END;
/

-- ЭТАП 12: Тестирование ходов
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    DBMS_OUTPUT.PUT_LINE('[OK] Ходы протестированы');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Ходы: ' || SQLERRM);
END;
/

-- ЭТАП 13: Параметры игры
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600,
        p_draw_moves_limit => 15,
        p_enable_pos_rep_draw => 'Y'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Игра с параметрами создана');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Параметры игры: ' || SQLERRM);
END;
/

-- ЭТАП 14: Ошибки и валидация
BEGIN
    C##CHECKERS_APP.game_logic.make_move('z9-z10');
    DBMS_OUTPUT.PUT_LINE('[WARN] Неверный ход не отклонен');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[OK] Неверный ход отклонен: ' || SQLERRM);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_game;
    C##CHECKERS_APP.game_logic.create_game;
    DBMS_OUTPUT.PUT_LINE('[WARN] Вторая игра не отклонена');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[OK] Вторая игра отклонена');
END;
/

-- ЭТАП 15: Режим зрителя
BEGIN
    C##CHECKERS_APP.game_logic.print_active_board(p_username => 'C##DEV2_USER');
    C##CHECKERS_APP.game_logic.stop_spectating;
    DBMS_OUTPUT.PUT_LINE('[OK] Режим зрителя протестирован');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Режим зрителя: ' || SQLERRM);
END;
/

-- ЭТАП 16: Решение задачи
BEGIN
    C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => 1);
    C##CHECKERS_APP.game_logic.print_active_board;
    DBMS_OUTPUT.PUT_LINE('[OK] Решение задачи начато');
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('[ERR] Решение задачи: ' || SQLERRM);
END;
/

DBMS_OUTPUT.PUT_LINE('=== ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ===');
