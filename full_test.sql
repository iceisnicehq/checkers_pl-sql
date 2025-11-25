SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- Очистка
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    DELETE FROM C##CHECKERS_APP.matches;
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DELETE FROM C##CHECKERS_APP.spectators;
    COMMIT;
END;
/

-- Информация
BEGIN
    C##CHECKERS_APP.game_logic.info;
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.info(p_proc_name => 'CREATE_GAME');
END;
/

-- Базовые функции
DECLARE
    v_test_8x8 VARCHAR2(64) := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
    v_encoded VARCHAR2(128);
    v_decoded VARCHAR2(128);
BEGIN
    v_encoded := C##CHECKERS_APP.game_logic.encode_board(v_test_8x8);
    v_decoded := C##CHECKERS_APP.game_logic.decode_board(v_encoded);
    C##CHECKERS_APP.game_logic.p_init_board_map(8);
    DBMS_OUTPUT.PUT_LINE('encode/decode: ' || CASE WHEN v_decoded = v_test_8x8 THEN 'OK' ELSE 'FAIL' END);
END;
/

-- PvP 8x8: создание, ходы, завершение
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- PvP 10x10: создание, ходы, завершение
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 2,
        p_time_limit_move_sec => 120
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- PvE Easy 8x8: создание, ходы, завершение
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('b6-a5');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.resign_game;
END;
/

-- PvE Medium 8x8: создание, ходы, ничья
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'M',
        p_player_color => 'B',
        p_rule_id => 1,
        p_draw_moves_limit => 5
    );
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('f6-e5');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.draw('O');
END;
/

-- PvE Hard 10x10: создание, ходы, завершение
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'H',
        p_player_color => 'W',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.resign_game;
END;
/

-- Ничья по соглашению
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.draw('O');
    C##CHECKERS_APP.game_logic.draw('A');
END;
/

-- Создание задач
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
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_puzzle(
        p_board_position => v_board_10x10,
        p_turn_to_move => 'B',
        p_moves_to_solve => 5,
        p_difficulty_level => 2
    );
END;
/

-- Просмотр задач
BEGIN
    C##CHECKERS_APP.game_logic.show_puzzles;
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 1);
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_my_puzzles;
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.show_daily_puzzle;
END;
/

-- Решение задачи
BEGIN
    C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => 1);
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('b6-a5');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- Матч: создание
BEGIN
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1
    );
END;
/

-- Просмотр доски
BEGIN
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.print_active_board(p_wait_for_turn => 'Y');
END;
/

-- Управление игрой
BEGIN
    C##CHECKERS_APP.game_logic.create_game;
    C##CHECKERS_APP.game_logic.cancel_game;
END;
/

BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.resign_game;
END;
/

-- Режим зрителя
BEGIN
    C##CHECKERS_APP.game_logic.print_active_board(p_username => 'C##DEV2_USER');
    C##CHECKERS_APP.game_logic.stop_spectating;
END;
/

-- Представления
BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_open_games FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_active_games FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_status WHERE ROWNUM <= 3) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_game_protocol WHERE ROWNUM <= 5 ORDER BY game_id, move_number) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_history_by_period FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_player_stats) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_leaderboard_by_avg_moves FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

BEGIN
    FOR r IN (SELECT * FROM C##CHECKERS_APP.v_daily_puzzle_results FETCH FIRST 3 ROWS ONLY) LOOP
        NULL;
    END LOOP;
END;
/

-- Тестирование ходов с взятиями
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('b6-a5');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('d4-c5');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- Параметры игры
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
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- Игра с лимитом ходов без взятий
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1,
        p_draw_moves_limit => 3
    );
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('b6-a5');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('d4-c5');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- Игра с повтором позиции
BEGIN
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1,
        p_enable_pos_rep_draw => 'Y'
    );
    C##CHECKERS_APP.game_logic.make_move('c3-d4');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('b6-a5');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('d4-c3');
    C##CHECKERS_APP.game_logic.print_active_board;
    C##CHECKERS_APP.game_logic.make_move('a5-b6');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/
