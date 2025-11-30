SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =========================================================================
-- ПОЛНЫЙ ТЕСТ ВСЕГО ФУНКЦИОНАЛА "ШАШКИ НА ORACLE"
-- =========================================================================
-- Этот файл содержит тесты для всех процедур и функций пакета game_logic
-- Игры нужно играть вручную - здесь только создание и инструкции
-- =========================================================================

-- =========================================================================
-- ШАБЛОНЫ ДЛЯ ИСПОЛЬЗОВАНИЯ
-- =========================================================================

/*
=== КАК СДЕЛАТЬ ХОД ===

-- Простой ход (без взятия):
BEGIN game_logic.make_move('c3-d4'); END;

-- Ход с взятием (используйте двоеточие, НЕ 'x'):
BEGIN game_logic.make_move('c3:e5'); END;

-- Множественное взятие:
BEGIN game_logic.make_move('c3:e5:g7'); END;

=== КАК ПОКАЗАТЬ ДОСКУ ===

-- Показать доску текущей игры (обычный режим):
BEGIN game_logic.print_active_board; END;

-- Показать доску и ждать своего хода (автоматическое обновление каждые 3 секунды, таймаут 5 минут):
BEGIN game_logic.print_active_board(p_wait_for_turn => 'Y'); END;

-- Показать доску как зритель (для другого пользователя):
BEGIN game_logic.print_active_board(p_username => 'C##DEV2_USER'); END;

-- Показать конкретную игру:
BEGIN game_logic.print_active_board(p_game_id => 123); END;

=== КАК ПРИСОЕДИНИТЬСЯ К ИГРЕ ===

-- Присоединиться к открытой игре или принять вызов:
BEGIN game_logic.join_game(p_game_id => 123); END;

=== КАК УПРАВЛЯТЬ НИЧЬЕЙ ===

-- Предложить ничью:
BEGIN game_logic.draw('O'); END;

-- Принять ничью:
BEGIN game_logic.draw('A'); END;

-- Отозвать свое предложение:
BEGIN game_logic.draw('C'); END;

=== КАК СДАТЬСЯ ===

-- Сдаться в текущей игре:
BEGIN game_logic.resign_game; END;

-- Сдаться во всем матче:
BEGIN game_logic.resign_game(p_resign_match => 'Y'); END;

=== КАК ОТМЕНИТЬ ИГРУ ===

-- Отменить открытую игру или вызов:
BEGIN game_logic.cancel_game; END;

=== КАК ПРОСМАТРИВАТЬ РЕПЛЕЙ ===

-- Просмотреть ходы завершенной игры:
BEGIN game_logic.watch_game_replay(p_game_id => 123); END;

-- Просмотреть несколько ходов за раз:
BEGIN game_logic.watch_game_replay(p_game_id => 123, p_moves_to_show => 5); END;

=== КАК ВЫЙТИ ИЗ РЕЖИМА ПРОСМОТРА ===

BEGIN game_logic.stop_spectating; END;

*/

-- =========================================================================
-- ОЧИСТКА ПЕРЕД ТЕСТИРОВАНИЕМ
-- =========================================================================
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    DELETE FROM C##CHECKERS_APP.matches;
    DELETE FROM C##CHECKERS_APP.puzzles WHERE created_by_player_id IS NOT NULL;
    DELETE FROM C##CHECKERS_APP.spectators;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('=== Очистка завершена ===');
END;
/

-- =========================================================================
-- 1. ИНФОРМАЦИЯ О ПАКЕТЕ
-- =========================================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ИНФОРМАЦИЯ О ПАКЕТЕ (краткая) ===');
    C##CHECKERS_APP.game_logic.info;
END;
/

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ИНФОРМАЦИЯ О CREATE_GAME ===');
    C##CHECKERS_APP.game_logic.info(p_query => 'CREATE_GAME');
END;
/

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ИНФОРМАЦИЯ О VIEWS ===');
    C##CHECKERS_APP.game_logic.info(p_query => 'VIEWS');
END;
/

-- =========================================================================
-- 2. ТЕСТИРОВАНИЕ ВАЛИДАЦИИ И ОШИБОК
-- =========================================================================

-- 2.1. Попытка создать игру с несовместимыми параметрами (PvE + таймауты)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE С ТАЙМАУТАМИ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_time_limit_move_sec => 60
    );
END;
/

-- 2.2. Попытка создать задачу с несовместимыми параметрами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ЗАДАЧА С ТАЙМАУТАМИ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_puzzle_id => 1,
        p_time_limit_move_sec => 60
    );
END;
/

-- 2.3. Попытка создать задачу с выбором цвета
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ЗАДАЧА С ВЫБОРОМ ЦВЕТА (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_puzzle_id => 1,
        p_player_color => 'W'
    );
END;
/

-- 2.4. Попытка создать игру с конфликтующими параметрами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: КОНФЛИКТ ПАРАМЕТРОВ (PvP + PvE) (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_ai_difficulty => 'E'
    );
END;
/

-- 2.5. Попытка создать игру с конфликтующими параметрами (PvP + Puzzle)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: КОНФЛИКТ ПАРАМЕТРОВ (PvP + Puzzle) (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_puzzle_id => 1
    );
END;
/

-- 2.6. Попытка создать матч с четным games_to_win
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: МАТЧ С ЧЕТНЫМ games_to_win (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 4
    );
END;
/

-- 2.7. Попытка создать игру с неверным цветом
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: НЕВЕРНЫЙ ЦВЕТ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'X'
    );
END;
/

-- 2.8. Попытка создать игру с отрицательным таймаутом
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОТРИЦАТЕЛЬНЫЙ ТАЙМАУТ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_time_limit_move_sec => -10
    );
END;
/

-- 2.9. Попытка присоединиться к несуществующей игре
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME НЕСУЩЕСТВУЮЩЕЙ ИГРЫ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => 99999);
END;
/

-- 2.10. Попытка присоединиться к активной игре
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME АКТИВНОЙ ИГРЫ (должна быть ошибка) ===');
    -- Сначала создаем игру и присоединяемся
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_rule_id => 1
    );
    -- Пытаемся присоединиться еще раз (должна быть ошибка)
    -- C##CHECKERS_APP.game_logic.join_game(p_game_id => <ID>);
END;
/

-- =========================================================================
-- 3. РЕГУЛЯРНЫЕ ИГРЫ PvP (РУССКИЕ 8x8)
-- =========================================================================

-- 3.1. PvP 8x8: создание прямого вызова
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 - ПРЯМОЙ ВЫЗОВ ===');
    DBMS_OUTPUT.PUT_LINE('Создан вызов игроку C##DEV2_USER');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Переключитесь на пользователя C##DEV2_USER');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.join_game(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Играйте по очереди, используя make_move()');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 3.2. PvP 8x8: создание открытой игры
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 - ОТКРЫТАЯ ИГРА ===');
    DBMS_OUTPUT.PUT_LINE('Создана открытая игра');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Проверьте v_open_games для получения game_id');
    DBMS_OUTPUT.PUT_LINE('  2. Переключитесь на другого пользователя');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.join_game(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Играйте по очереди');
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 3.3. PvP 8x8: с таймаутами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 С ТАЙМАУТАМИ ===');
    DBMS_OUTPUT.PUT_LINE('Создана игра с таймаутами: 60 сек на ход, 3600 сек на партию');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте и проверьте работу таймаутов');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что при превышении таймаута игра завершается');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 3.4. PvP 8x8: с лимитом ходов без взятий
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 С ЛИМИТОМ ХОДОВ БЕЗ ВЗЯТИЙ ===');
    DBMS_OUTPUT.PUT_LINE('Создана игра с лимитом 15 полуходов без взятий');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  2. Сделайте 15 полуходов без взятий');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра завершилась ничьей');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_draw_moves_limit => 15
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 3.5. PvP 8x8: с повтором позиции
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 С ПОВТОРОМ ПОЗИЦИИ ===');
    DBMS_OUTPUT.PUT_LINE('Создана игра с включенным повтором позиции');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  2. Повторите позицию 3 раза');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра завершилась ничьей');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_enable_pos_rep_draw => 'Y'
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 3.6. PvP 8x8: со всеми параметрами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 СО ВСЕМИ ПАРАМЕТРАМИ ===');
    DBMS_OUTPUT.PUT_LINE('Создана игра со всеми параметрами');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте и проверьте работу всех параметров');
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

-- 3.7. PvP 8x8: отмена игры
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 - ОТМЕНА ИГРЫ ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.cancel_game;
END;
/

-- 3.8. PvP 8x8: сдача
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 8x8 - СДАЧА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру и присоединитесь');
    DBMS_OUTPUT.PUT_LINE('  2. Сделайте несколько ходов');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.resign_game; END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что игра завершилась');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 4. РЕГУЛЯРНЫЕ ИГРЫ PvP (МЕЖДУНАРОДНЫЕ 10x10)
-- =========================================================================

-- 4.1. PvP 10x10: создание прямого вызова
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 10x10 - ПРЯМОЙ ВЫЗОВ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте и проверьте правила международных шашек');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте обязательное максимальное взятие');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 4.2. PvP 10x10: открытая игра
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 10x10 - ОТКРЫТАЯ ИГРА ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 4.3. PvP 10x10: со всеми параметрами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvP 10x10 СО ВСЕМИ ПАРАМЕТРАМИ ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 2,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600,
        p_draw_moves_limit => 15,
        p_enable_pos_rep_draw => 'Y'
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 5. ИГРЫ С ИИ (PvE) - РУССКИЕ 8x8
-- =========================================================================

-- 5.1. PvE Easy 8x8
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE EASY 8x8 ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Играйте против ИИ Easy');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что ИИ делает валидные ходы');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте работу всех правил (взятия, превращения)');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
    DBMS_OUTPUT.PUT_LINE('Сделайте ход: BEGIN game_logic.make_move(''c3-d4''); END;');
END;
/

-- 5.2. PvE Medium 8x8
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE MEDIUM 8x8 ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Играйте против ИИ Medium');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что ИИ играет лучше, чем Easy');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'M',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 5.3. PvE Hard 8x8
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE HARD 8x8 ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Играйте против ИИ Hard');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что ИИ играет на высоком уровне');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'H',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 5.4. PvE: проверка, что ИИ ходит первым (если выбраны черные)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE - ИИ ХОДИТ ПЕРВЫМ (ЧЕРНЫЕ) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Проверьте, что ИИ сделал первый ход');
    DBMS_OUTPUT.PUT_LINE('  2. Сделайте свой ход');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'B',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 5.5. PvE: сдача
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE - СДАЧА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Сделайте несколько ходов');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.resign_game; END;');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 5.6. PvE: ничья по соглашению (должна быть ошибка)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE - НИЧЬЯ (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.draw('O');
END;
/

-- =========================================================================
-- 6. ИГРЫ С ИИ (PvE) - МЕЖДУНАРОДНЫЕ 10x10
-- =========================================================================

-- 6.1. PvE Easy 10x10
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE EASY 10x10 ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Играйте против ИИ на доске 10x10');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте правила международных шашек');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 6.2. PvE Medium 10x10
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE MEDIUM 10x10 ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'M',
        p_player_color => 'W',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 6.3. PvE Hard 10x10
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: PvE HARD 10x10 ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'H',
        p_player_color => 'W',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 7. ЗАДАЧИ (PUZZLES)
-- =========================================================================

-- 7.1. Создание задачи 8x8
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ ЗАДАЧИ 8x8 ===');
    DECLARE
        v_board_8x8 CLOB := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
    BEGIN
        C##CHECKERS_APP.game_logic.create_puzzle(
            p_board_position => v_board_8x8,
            p_turn_to_move => 'W',
            p_moves_to_solve => 3,
            p_difficulty_level => 'M',
            p_solution => 'c3:e5:g7'
        );
    END;
END;
/

-- 7.2. Создание задачи 10x10
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ ЗАДАЧИ 10x10 ===');
    DECLARE
        v_board_10x10 CLOB := '+b+b+b+b+bb+b+b+b+b+b++++++++++w+w+w+w+w+w+w+w+w+';
    BEGIN
        C##CHECKERS_APP.game_logic.create_puzzle(
            p_board_position => v_board_10x10,
            p_turn_to_move => 'B',
            p_moves_to_solve => 5,
            p_difficulty_level => 'H',
            p_solution => 'c3:e5:g7:i9'
        );
    END;
END;
/

-- 7.3. Создание задачи с end_board_state (ничья)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ ЗАДАЧИ С END_BOARD_STATE ===');
    DECLARE
        v_board CLOB := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
        v_end_board CLOB := '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++';
    BEGIN
        -- Сначала нужно закодировать end_board_state
        -- C##CHECKERS_APP.game_logic.create_puzzle(...);
    END;
END;
/

-- 7.4. Создание задачи без moves_to_solve (игра с ИИ)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ ЗАДАЧИ БЕЗ moves_to_solve ===');
    DECLARE
        v_board CLOB := '+b+b+b+bb+b+b+b++++++++w+w+w+w+w+w+w+w+';
    BEGIN
        C##CHECKERS_APP.game_logic.create_puzzle(
            p_board_position => v_board,
            p_turn_to_move => 'W',
            p_moves_to_solve => NULL,
            p_difficulty_level => 'M'
        );
    END;
END;
/

-- 7.5. Просмотр всех задач
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР ВСЕХ ЗАДАЧ ===');
    C##CHECKERS_APP.game_logic.show_puzzles;
END;
/

-- 7.6. Просмотр задач по сложности
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР ЗАДАЧ ПО СЛОЖНОСТИ ===');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 'E');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 'M');
    C##CHECKERS_APP.game_logic.show_puzzles(p_difficulty => 'H');
END;
/

-- 7.7. Просмотр конкретной задачи
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР КОНКРЕТНОЙ ЗАДАЧИ ===');
    C##CHECKERS_APP.game_logic.show_puzzles(p_puzzle_id => 1);
END;
/

-- 7.8. Просмотр решения задачи (после попытки)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР РЕШЕНИЯ ЗАДАЧИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с задачей: BEGIN game_logic.create_game(p_puzzle_id => 1); END;');
    DBMS_OUTPUT.PUT_LINE('  2. Сделайте хотя бы один ход');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.show_puzzles(p_puzzle_id => 1, p_solution => ''Y''); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что решение показывается');
    DBMS_OUTPUT.PUT_LINE('  5. Попробуйте посмотреть решение без попытки (должна быть ошибка)');
END;
/

-- 7.9. Просмотр моих задач
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР МОИХ ЗАДАЧ ===');
    C##CHECKERS_APP.game_logic.show_my_puzzles;
END;
/

-- 7.10. Удаление моей задачи
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: УДАЛЕНИЕ МОЕЙ ЗАДАЧИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте задачу (см. тест 7.1)');
    DBMS_OUTPUT.PUT_LINE('  2. Получите puzzle_id из вывода');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.delete_my_puzzle(<ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что задача удалена');
    DBMS_OUTPUT.PUT_LINE('  5. Попробуйте удалить все свои задачи: BEGIN game_logic.delete_my_puzzle(0); END;');
END;
/

-- 7.11. Просмотр задачи дня
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР ЗАДАЧИ ДНЯ ===');
    C##CHECKERS_APP.game_logic.show_daily_puzzle;
END;
/

-- 7.12. Решение задачи
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: РЕШЕНИЕ ЗАДАЧИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с задачей: BEGIN game_logic.create_game(p_puzzle_id => 1); END;');
    DBMS_OUTPUT.PUT_LINE('  2. Решите задачу за оптимальное количество ходов');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что puzzle_status = ''s'' (solved)');
    DBMS_OUTPUT.PUT_LINE('  4. Попробуйте решить за больше ходов - должно показать решение');
    DBMS_OUTPUT.PUT_LINE('  5. Попробуйте не решить - должно быть puzzle_status = ''f'' (failed)');
    C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => 1);
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 7.13. Решение задачи дня
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: РЕШЕНИЕ ЗАДАЧИ ДНЯ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с задачей дня: BEGIN game_logic.create_game(p_daily => ''Y''); END;');
    DBMS_OUTPUT.PUT_LINE('  2. Решите задачу');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте рейтинг (+5 за первое решение)');
    C##CHECKERS_APP.game_logic.create_game(p_daily => 'Y');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 8. МАТЧИ (MATCHES)
-- =========================================================================

-- 8.1. Создание матча (best of 3)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ МАТЧА (BEST OF 3) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Переключитесь на пользователя C##DEV2_USER');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.join_match(p_match_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Играйте игры в матче');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что после каждой игры создается следующая');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что после победы в 2 играх матч завершается');
    DBMS_OUTPUT.PUT_LINE('  6. Проверьте обновление рейтинга матча (+10*N бонус)');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1
    );
END;
/

-- 8.2. Создание матча (best of 5)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ МАТЧА (BEST OF 5) ===');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 5,
        p_player_color => 'W',
        p_rule_id => 1
    );
END;
/

-- 8.3. Создание матча со всеми параметрами
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ МАТЧА СО ВСЕМИ ПАРАМЕТРАМИ ===');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600,
        p_draw_moves_limit => 15,
        p_enable_pos_rep_draw => 'Y'
    );
END;
/

-- 8.4. Создание матча 10x10
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ МАТЧА 10x10 ===');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 2
    );
END;
/

-- 8.5. Присоединение к матчу
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРИСОЕДИНЕНИЕ К МАТЧУ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте матч от другого пользователя');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.join_match(p_match_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что первая игра началась');
END;
/

-- =========================================================================
-- 9. РЕЖИМ ЗРИТЕЛЯ (SPECTATING)
-- =========================================================================

-- 9.1. Просмотр активной игры другого пользователя
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР ИГРЫ ДРУГОГО ПОЛЬЗОВАТЕЛЯ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру от другого пользователя');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.print_active_board(p_username => ''C##DEV2_USER''); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что вы вошли в режим просмотра');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что доска обновляется');
END;
/

-- 9.2. Просмотр конкретной игры
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР КОНКРЕТНОЙ ИГРЫ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Получите game_id активной игры');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.print_active_board(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте режим просмотра');
END;
/

-- 9.3. Ожидание хода (автоматическое обновление)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОЖИДАНИЕ ХОДА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру или войдите в режим просмотра');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что доска обновляется каждые 3 секунды');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте таймаут ожидания (5 минут)');
END;
/

-- 9.4. Остановка просмотра
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОСТАНОВКА ПРОСМОТРА ===');
    C##CHECKERS_APP.game_logic.stop_spectating;
END;
/

-- 9.5. Просмотр реплея игры
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРОСМОТР РЕПЛЕЯ ИГРЫ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Завершите игру (победа, ничья, сдача)');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.watch_game_replay(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Просматривайте ходы пошагово');
    DBMS_OUTPUT.PUT_LINE('  4. Выполните еще раз для следующего хода');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте просмотр нескольких ходов: BEGIN game_logic.watch_game_replay(p_game_id => <ID>, p_moves_to_show => 5); END;');
END;
/

-- =========================================================================
-- 10. УПРАВЛЕНИЕ НИЧЬЕЙ
-- =========================================================================

-- 10.1. Предложение ничьей
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРЕДЛОЖЕНИЕ НИЧЬЕЙ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте PvP игру и присоединитесь');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.draw(''O''); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что предложение отображается в print_active_board');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 10.2. Принятие ничьей
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРИНЯТИЕ НИЧЬЕЙ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Предложите ничью от одного игрока');
    DBMS_OUTPUT.PUT_LINE('  2. Переключитесь на другого игрока');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.draw(''A''); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что игра завершилась ничьей');
END;
/

-- 10.3. Отзыв предложения ничьей
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОТЗЫВ ПРЕДЛОЖЕНИЯ НИЧЬЕЙ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Предложите ничью');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните: BEGIN game_logic.draw(''C''); END;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что предложение отозвано');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.draw('O');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 10.4. Автоматическая ничья (оба предложили)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: АВТОМАТИЧЕСКАЯ НИЧЬЯ (ОБА ПРЕДЛОЖИЛИ) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Первый игрок предлагает ничью');
    DBMS_OUTPUT.PUT_LINE('  2. Второй игрок тоже предлагает ничью');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра автоматически завершилась ничьей');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.draw('O');
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 10.5. Ничья по лимиту ходов без взятий
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: НИЧЬЯ ПО ЛИМИТУ ХОДОВ БЕЗ ВЗЯТИЙ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с draw_moves_limit => 10');
    DBMS_OUTPUT.PUT_LINE('  2. Сделайте 10 полуходов без взятий');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра завершилась ничьей');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_draw_moves_limit => 10
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 10.6. Ничья по повтору позиции
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: НИЧЬЯ ПО ПОВТОРУ ПОЗИЦИИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с enable_pos_rep_draw => ''Y''');
    DBMS_OUTPUT.PUT_LINE('  2. Повторите позицию 3 раза');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра завершилась ничьей');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_enable_pos_rep_draw => 'Y'
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 11. ТЕСТИРОВАНИЕ ТАЙМАУТОВ
-- =========================================================================

-- 11.1. Таймаут хода
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ТАЙМАУТ ХОДА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с очень коротким таймаутом хода (например, 10 секунд)');
    DBMS_OUTPUT.PUT_LINE('  2. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  3. Подождите 11+ секунд');
    DBMS_OUTPUT.PUT_LINE('  4. Попробуйте сделать ход - должна быть ошибка таймаута');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что игра завершилась, победитель - оппонент');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 10
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 11.2. Таймаут партии
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ТАЙМАУТ ПАРТИИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с очень коротким таймаутом партии (например, 30 секунд)');
    DBMS_OUTPUT.PUT_LINE('  2. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  3. Подождите 31+ секунд');
    DBMS_OUTPUT.PUT_LINE('  4. Попробуйте сделать ход - игра должна быть завершена по таймауту');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что победитель определен по оценке позиции');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_game_sec => 30
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 11.3. Таймаут хода и партии одновременно
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ТАЙМАУТ ХОДА И ПАРТИИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Играйте и проверьте работу обоих таймаутов');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1,
        p_time_limit_move_sec => 60,
        p_time_limit_game_sec => 3600
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 12. ТЕСТИРОВАНИЕ ПРАВИЛ ИГРЫ
-- =========================================================================

-- 12.1. Русские шашки 8x8: обязательное взятие, но можно выбрать любое
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: РУССКИЕ ШАШКИ - ОБЯЗАТЕЛЬНОЕ ВЗЯТИЕ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию с несколькими вариантами взятия');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что можно выбрать любой вариант взятия');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что ход без взятия запрещен, если есть взятие');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 12.2. Международные шашки 10x10: обязательное максимальное взятие
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: МЕЖДУНАРОДНЫЕ ШАШКИ - МАКСИМАЛЬНОЕ ВЗЯТИЕ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию с несколькими вариантами взятия');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что доступны только варианты с максимальным количеством фигур');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что ход с меньшим количеством фигур запрещен');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 12.3. Превращение в дамку
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПРЕВРАЩЕНИЕ В ДАМКУ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию, где простая шашка может достичь последней горизонтали');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что превращение происходит немедленно');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что дамка может продолжать взятие');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 12.4. Множественное взятие
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: МНОЖЕСТВЕННОЕ ВЗЯТИЕ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию с возможностью множественного взятия');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что можно взять несколько фигур за один ход');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте нотацию: c3:e5:g7');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 12.5. Пат (нет ходов)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПАТ (НЕТ ХОДОВ) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию, где у игрока нет ходов');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте сделать ход - должна быть ошибка');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что игра завершилась, победитель - оппонент');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 12.6. Победа (нет фигур противника)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПОБЕДА (НЕТ ФИГУР ПРОТИВНИКА) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию, где у противника нет фигур');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что игра завершилась победой');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 13. ТЕСТИРОВАНИЕ JOIN_GAME
-- =========================================================================

-- 13.1. Присоединение к открытой игре
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME - ОТКРЫТАЯ ИГРА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте открытую игру (без opponent_username)');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте v_open_games для получения game_id и your_color');
    DBMS_OUTPUT.PUT_LINE('  3. Переключитесь на другого пользователя');
    DBMS_OUTPUT.PUT_LINE('  4. Выполните: BEGIN game_logic.join_game(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что игра стала активной (status = ''A'')');
    DBMS_OUTPUT.PUT_LINE('  6. Проверьте, что вы получили правильный цвет (your_color из v_open_games)');
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 13.2. Принятие прямого вызова
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME - ПРИНЯТИЕ ВЫЗОВА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте прямой вызов (с opponent_username)');
    DBMS_OUTPUT.PUT_LINE('  2. Переключитесь на вызванного пользователя');
    DBMS_OUTPUT.PUT_LINE('  3. Выполните: BEGIN game_logic.join_game(p_game_id => <ID>); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что игра стала активной');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что создатель не может создать новую игру (статус C блокирует)');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 13.3. Попытка присоединиться к своей игре
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME - СВОЯ ИГРА (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1
    );
    -- Попытка присоединиться к своей игре
    -- C##CHECKERS_APP.game_logic.join_game(p_game_id => <ID>);
END;
/

-- 13.4. Попытка присоединиться к чужому вызову
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME - ЧУЖОЙ ВЫЗОВ (должна быть ошибка) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте вызов от USER1 к USER2');
    DBMS_OUTPUT.PUT_LINE('  2. Переключитесь на USER3');
    DBMS_OUTPUT.PUT_LINE('  3. Попробуйте присоединиться - должна быть ошибка');
END;
/

-- 13.5. Присоединение с таймаутом хода
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: JOIN_GAME - С ТАЙМАУТОМ ХОДА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с таймаутом хода');
    DBMS_OUTPUT.PUT_LINE('  2. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что создан джоб таймаута');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что таймаут работает');
    C##CHECKERS_APP.game_logic.create_game(
        p_rule_id => 1,
        p_time_limit_move_sec => 60
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 14. ПРЕДСТАВЛЕНИЯ (VIEWS) - SELECT ЗАПРОСЫ
-- =========================================================================

-- 14.1. Открытые игры
PROMPT === ПРЕДСТАВЛЕНИЕ: v_open_games ===
SELECT * FROM C##CHECKERS_APP.v_open_games ORDER BY game_id DESC FETCH FIRST 10 ROWS ONLY;

-- 14.2. Активные игры
PROMPT === ПРЕДСТАВЛЕНИЕ: v_active_games ===
SELECT * FROM C##CHECKERS_APP.v_active_games ORDER BY game_id DESC FETCH FIRST 10 ROWS ONLY;

-- 14.3. Статус игры
PROMPT === ПРЕДСТАВЛЕНИЕ: v_game_status ===
SELECT * FROM C##CHECKERS_APP.v_game_status WHERE game_id IN (SELECT game_id FROM C##CHECKERS_APP.games ORDER BY game_id DESC FETCH FIRST 5 ROWS ONLY) ORDER BY game_id DESC;

-- 14.4. Протокол игры
PROMPT === ПРЕДСТАВЛЕНИЕ: v_game_protocol ===
SELECT * FROM C##CHECKERS_APP.v_game_protocol WHERE game_id IN (SELECT game_id FROM C##CHECKERS_APP.games WHERE status IN ('V', 'D', 'T', 'R') ORDER BY game_id DESC FETCH FIRST 3 ROWS ONLY) ORDER BY game_id, move_number;

-- 14.5. История игрока
PROMPT === ПРЕДСТАВЛЕНИЕ: v_player_history ===
SELECT * FROM C##CHECKERS_APP.v_player_history ORDER BY end_time DESC FETCH FIRST 10 ROWS ONLY;

-- 14.6. История игрока за период
PROMPT === ПРЕДСТАВЛЕНИЕ: v_player_history_by_period ===
SELECT * FROM C##CHECKERS_APP.v_player_history_by_period FETCH FIRST 10 ROWS ONLY;

-- 14.7. Статистика игрока
PROMPT === ПРЕДСТАВЛЕНИЕ: v_player_stats ===
SELECT * FROM C##CHECKERS_APP.v_player_stats;

-- 14.8. Рейтинг по успеху
PROMPT === ПРЕДСТАВЛЕНИЕ: v_leaderboard ===
SELECT * FROM C##CHECKERS_APP.v_leaderboard FETCH FIRST 10 ROWS ONLY;

-- 14.9. Рейтинг по среднему числу ходов
PROMPT === ПРЕДСТАВЛЕНИЕ: v_leaderboard_by_avg_moves ===
SELECT * FROM C##CHECKERS_APP.v_leaderboard_by_avg_moves FETCH FIRST 10 ROWS ONLY;

-- 14.10. Результаты Daily Puzzles
PROMPT === ПРЕДСТАВЛЕНИЕ: v_daily_puzzle_results ===
SELECT * FROM C##CHECKERS_APP.v_daily_puzzle_results ORDER BY puzzle_date DESC FETCH FIRST 10 ROWS ONLY;

-- =========================================================================
-- 15. РЕЙТИНГИ И СЕЗОНЫ
-- =========================================================================

-- 15.1. Проверка создания рейтингов для нового игрока
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ РЕЙТИНГОВ ДЛЯ НОВОГО ИГРОКА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте нового пользователя (или используйте несуществующего)');
    DBMS_OUTPUT.PUT_LINE('  2. Выполните любую операцию (например, create_game)');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что созданы рейтинги для всех правил в текущем сезоне (начальный рейтинг = 500)');
    DBMS_OUTPUT.PUT_LINE('  4. SELECT * FROM player_ratings WHERE player_id = <ID>;');
END;
/

-- 15.2. Проверка обновления рейтинга после победы
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОБНОВЛЕНИЕ РЕЙТИНГА ПОСЛЕ ПОБЕДЫ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте PvP игру');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте до завершения (победа одного из игроков)');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте рейтинги: победитель +16, проигравший -16');
    DBMS_OUTPUT.PUT_LINE('  4. SELECT * FROM player_ratings WHERE player_id IN (<ID1>, <ID2>);');
END;
/

-- 15.3. Проверка обновления рейтинга после решения задачи
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОБНОВЛЕНИЕ РЕЙТИНГА ПОСЛЕ РЕШЕНИЯ ЗАДАЧИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Решите общую задачу (created_by_player_id IS NULL) впервые');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте рейтинг: +5 очков');
    DBMS_OUTPUT.PUT_LINE('  3. Решите ту же задачу еще раз - рейтинг не должен измениться');
    DBMS_OUTPUT.PUT_LINE('  4. SELECT * FROM player_ratings WHERE player_id = <ID>;');
END;
/

-- 15.4. Проверка обновления рейтинга матча
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ОБНОВЛЕНИЕ РЕЙТИНГА МАТЧА ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте матч (best of 3)');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте игры в матче');
    DBMS_OUTPUT.PUT_LINE('  3. После завершения матча проверьте рейтинги:');
    DBMS_OUTPUT.PUT_LINE('     - +16 за каждую победу в игре');
    DBMS_OUTPUT.PUT_LINE('     - -16 за каждое поражение в игре');
    DBMS_OUTPUT.PUT_LINE('     - +10*N бонус за матч (N = games_to_win)');
    DBMS_OUTPUT.PUT_LINE('  4. SELECT * FROM player_ratings WHERE player_id IN (<ID1>, <ID2>);');
END;
/

-- 15.5. Проверка сезонов
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СЕЗОНЫ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Проверьте текущий сезон: SELECT * FROM seasons WHERE SYSDATE BETWEEN start_date AND end_date;');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте, что рейтинги обновляются в сезоне начала игры');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что сезоны создаются автоматически (scheduler)');
    DBMS_OUTPUT.PUT_LINE('  4. SELECT * FROM seasons ORDER BY start_date DESC;');
END;
/

-- =========================================================================
-- 16. ТЕСТИРОВАНИЕ АВТОМАТИЧЕСКОГО ЗАВЕРШЕНИЯ НЕАКТИВНЫХ ИГР
-- =========================================================================

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: АВТОМАТИЧЕСКОЕ ЗАВЕРШЕНИЕ НЕАКТИВНЫХ ИГР ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру и сделайте несколько ходов');
    DBMS_OUTPUT.PUT_LINE('  2. Оставьте игру без ходов на 24+ часа');
    DBMS_OUTPUT.PUT_LINE('  3. Запустите вручную: BEGIN game_logic.p_process_inactive_timeouts(24); END;');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что игра завершена (status = ''T'')');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что победитель определен по оценке позиции (1:4 для шашка:дамка)');
    DBMS_OUTPUT.PUT_LINE('  6. Проверьте, что рейтинги обновлены');
END;
/

-- =========================================================================
-- 17. КОМПЛЕКСНЫЕ СЦЕНАРИИ
-- =========================================================================

-- 17.1. Полная игра PvP с завершением
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПОЛНАЯ ИГРА PvP ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте PvP игру');
    DBMS_OUTPUT.PUT_LINE('  2. Присоединитесь к игре');
    DBMS_OUTPUT.PUT_LINE('  3. Играйте до завершения (победа, ничья, сдача)');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте протокол игры: SELECT * FROM v_game_protocol WHERE game_id = <ID>;');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте обновление рейтингов');
    DBMS_OUTPUT.PUT_LINE('  6. Проверьте историю: SELECT * FROM v_player_history WHERE game_id = <ID>;');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 17.2. Полная игра PvE с завершением
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПОЛНАЯ ИГРА PvE ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте PvE игру');
    DBMS_OUTPUT.PUT_LINE('  2. Играйте до завершения');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что рейтинг НЕ обновляется (PvE не влияет на рейтинг)');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 17.3. Полный матч
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ПОЛНЫЙ МАТЧ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте матч (best of 3)');
    DBMS_OUTPUT.PUT_LINE('  2. Присоединитесь к матчу');
    DBMS_OUTPUT.PUT_LINE('  3. Играйте игры в матче');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что после каждой игры создается следующая');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что после победы в 2 играх матч завершается');
    DBMS_OUTPUT.PUT_LINE('  6. Проверьте обновление рейтинга матча');
    C##CHECKERS_APP.game_logic.create_match(
        p_opponent_username => 'C##DEV2_USER',
        p_games_to_win => 3,
        p_player_color => 'W',
        p_rule_id => 1
    );
END;
/

-- 17.4. Решение задачи с проверкой всех статусов
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: РЕШЕНИЕ ЗАДАЧИ - ВСЕ СТАТУСЫ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру с задачей (moves_to_solve = 3)');
    DBMS_OUTPUT.PUT_LINE('  2. Решите за 3 хода - должно быть puzzle_status = ''s''');
    DBMS_OUTPUT.PUT_LINE('  3. Создайте новую игру с той же задачей');
    DBMS_OUTPUT.PUT_LINE('  4. Решите за 5 ходов - должно показать решение и puzzle_status = ''s''');
    DBMS_OUTPUT.PUT_LINE('  5. Создайте новую игру с той же задачей');
    DBMS_OUTPUT.PUT_LINE('  6. Не решите (сдайтесь) - должно быть puzzle_status = ''f''');
    C##CHECKERS_APP.game_logic.create_game(p_puzzle_id => 1);
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 18. ПРОВЕРКА КОНКУРЕНТНОСТИ
-- =========================================================================

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: КОНКУРЕНТНОСТЬ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру и присоединитесь');
    DBMS_OUTPUT.PUT_LINE('  2. Откройте два терминала с одним пользователем');
    DBMS_OUTPUT.PUT_LINE('  3. Попробуйте сделать ход одновременно из обоих терминалов');
    DBMS_OUTPUT.PUT_LINE('  4. Проверьте, что принят только один валидный ход');
    DBMS_OUTPUT.PUT_LINE('  5. Проверьте, что второй ход отклонен');
END;
/

-- =========================================================================
-- 19. ПРОВЕРКА ОГРАНИЧЕНИЙ
-- =========================================================================

-- 19.1. Попытка создать вторую игру
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ВТОРАЯ ИГРА (должна быть ошибка) ===');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_rule_id => 1
    );
    -- Попытка создать вторую игру
    -- C##CHECKERS_APP.game_logic.create_game(p_ai_difficulty => 'E');
END;
/

-- 19.2. Попытка создать игру во время просмотра
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ИГРА ВО ВРЕМЯ ПРОСМОТРА (должна быть ошибка) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Войдите в режим просмотра');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте создать игру - должна быть ошибка');
    DBMS_OUTPUT.PUT_LINE('  3. Выйдите из режима просмотра: BEGIN game_logic.stop_spectating; END;');
    DBMS_OUTPUT.PUT_LINE('  4. Попробуйте создать игру - должно работать');
END;
/

-- 19.3. Попытка создать игру, когда есть вызов (статус C)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: СОЗДАНИЕ ИГРЫ ПРИ ВЫЗОВЕ (статус C) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте вызов (как создатель)');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте создать новую игру - должна быть ошибка (создатель заблокирован)');
    DBMS_OUTPUT.PUT_LINE('  3. Переключитесь на вызванного пользователя');
    DBMS_OUTPUT.PUT_LINE('  4. Попробуйте создать новую игру - должно работать (вызванный не заблокирован)');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
END;
/

-- =========================================================================
-- 20. ПРОВЕРКА ВАЛИДАЦИИ ХОДОВ
-- =========================================================================

-- 20.1. Неверный формат нотации
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: НЕВЕРНЫЙ ФОРМАТ НОТАЦИИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте сделать ход с неверной нотацией:');
    DBMS_OUTPUT.PUT_LINE('     - BEGIN game_logic.make_move(''c3xe5''); END; (должна быть ошибка, используйте '':'')');
    DBMS_OUTPUT.PUT_LINE('     - BEGIN game_logic.make_move(''invalid''); END; (должна быть ошибка)');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 20.2. Ход не своей очереди
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ХОД НЕ СВОЕЙ ОЧЕРЕДИ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте PvP игру');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте сделать ход, когда очередь оппонента - должна быть ошибка');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color => 'W',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 20.3. Ход без взятия, когда есть взятие
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ХОД БЕЗ ВЗЯТИЯ, КОГДА ЕСТЬ ВЗЯТИЕ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте позицию с возможностью взятия');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте сделать тихий ход - должна быть ошибка');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что показаны доступные варианты взятия');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 1
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- 20.4. Ход с меньшим взятием (для международных шашек)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: ХОД С МЕНЬШИМ ВЗЯТИЕМ (10x10) ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Создайте игру 10x10 с позицией, где есть несколько вариантов взятия');
    DBMS_OUTPUT.PUT_LINE('  2. Попробуйте сделать ход с меньшим количеством фигур - должна быть ошибка');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что доступны только варианты с максимальным количеством');
    C##CHECKERS_APP.game_logic.create_game(
        p_ai_difficulty => 'E',
        p_rule_id => 2
    );
    C##CHECKERS_APP.game_logic.print_active_board;
END;
/

-- =========================================================================
-- 21. ПРОВЕРКА АУДИТА
-- =========================================================================

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТ: АУДИТ ===');
    DBMS_OUTPUT.PUT_LINE('ИНСТРУКЦИЯ:');
    DBMS_OUTPUT.PUT_LINE('  1. Выполните различные действия (создание игры, ходы, завершение)');
    DBMS_OUTPUT.PUT_LINE('  2. Проверьте audit_log: SELECT * FROM audit_log ORDER BY log_timestamp DESC FETCH FIRST 20 ROWS ONLY;');
    DBMS_OUTPUT.PUT_LINE('  3. Проверьте, что все значимые события залогированы');
END;
/

-- =========================================================================
-- ЗАВЕРШЕНИЕ ТЕСТИРОВАНИЯ
-- =========================================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ===');
    DBMS_OUTPUT.PUT_LINE('Все тесты созданы. Играйте игры вручную и проверяйте функционал.');
    DBMS_OUTPUT.PUT_LINE('Используйте SELECT запросы для проверки VIEWS и статистики.');
END;
/
