-- @procedure info
-- @brief Displays help information about the game_logic package.
-- @dependencies:
--   - (none)

PROCEDURE info IS
    c_nl CONSTANT VARCHAR2(1) := CHR(10);
BEGIN
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle" (v1.2)');
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('Это главная справка по пакету game_logic. ');
    DBMS_OUTPUT.PUT_LINE('Для корректной работы справки убедитесь, что у вас включен DBMS_OUTPUT.');
    DBMS_OUTPUT.PUT_LINE('---');
    
    DBMS_OUTPUT.PUT_LINE('## 1. НАЧАЛО ИГРЫ (CREATE_GAME)');
    DBMS_OUTPUT.PUT_LINE('Вы можете начать 3 типа сессий:');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  А. Игра против ИИ (PvE):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
    DBMS_OUTPUT.PUT_LINE('     (Сложность: ''E'' - Easy, ''M'' - Medium, ''H'' - Hard)');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Б. Открытая игра (PvP):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game; END;');
    DBMS_OUTPUT.PUT_LINE('     (Создает игру, к которой может присоединиться любой желающий)');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  В. Прямой вызов (PvP):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_opponent_username => ''BOB''); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  * Выбор цвета (для PvP/PvE):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_player_color => ''W''); END; -- (Играть за Белых)');
    DBMS_OUTPUT.PUT_LINE('     (Если не указать, цвет будет выбран случайно)');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 2. ПРИСОЕДИНЕНИЕ К ИГРЕ (JOIN_GAME)');
    DBMS_OUTPUT.PUT_LINE('Если вас вызвали (или вы нашли ID открытой игры):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.join_game(p_game_id => 123); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 3. ИГРОВОЙ ПРОЦЕСС');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  А. Сделать ход (make_move):');
    DBMS_OUTPUT.PUT_LINE('     Используйте стандартную шашечную нотацию.');
    DBMS_OUTPUT.PUT_LINE('     Тихий ход: ''a3-b4''');
    DBMS_OUTPUT.PUT_LINE('     Взятие:    ''a3:c5'' (двоеточие обязательно)');
    DBMS_OUTPUT.PUT_LINE('     Multi-взятие: ''a3:c5:e7''');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.make_move(p_move_notation => ''c3-d4''); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Б. Посмотреть доску (print_active_board):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.print_active_board; END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  В. Сдаться (resign_game):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.resign_game; END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Г. Отменить ожидающую игру (cancel_game):');
    DBMS_OUTPUT.PUT_LINE('     (Работает, только если игра в статусе ''O'' или ''C'')');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.cancel_game; END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Д. Ничья (draw):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''O''); END; -- (O = Offer / Предложить)');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''A''); END; -- (A = Accept / Принять)');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.draw(p_action => ''C''); END; -- (C = Cancel-Decline / Отменить-Отклонить)');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 4. МАТЧИ (СЕРИИ ИГР)');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  А. Создать матч (до N побед):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_match(p_opponent_username => ''BOB'', p_games_to_win => 3); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Б. Присоединиться к матчу:');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.join_match(p_match_id => 456); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  В. Сдаться в матче (досрочно):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);
    
    DBMS_OUTPUT.PUT_LINE('## 5. ЗАДАЧИ (PUZZLES)');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  А. Посмотреть список задач:');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles; END;');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles(p_difficulty => 1); END;');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_puzzles(p_puzzle_id => 101); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Б. Задача Дня:');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_daily_puzzle; END;');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.start_daily_puzzle; END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  В. Начать любую задачу (по ID):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.create_game(p_puzzle_id => 101); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Г. Управление своими задачами:');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.show_my_puzzles; END;');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.delete_my_puzzle(p_puzzle_id => 102); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 6. ПРОСМОТР ИГР (ЗРИТЕЛЬ И РЕПЛЕИ)');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  А. Смотреть АКТИВНУЮ игру (Режим Зрителя):');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.print_active_board(p_username => ''BOB''); END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  Б. Выйти из режима Зрителя:');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.stop_watching; END;');
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('  В. Смотреть ЗАВЕРШЕННУЮ игру (Реплей):');
    DBMS_OUTPUT.PUT_LINE('     (Этот вызов создает сессию и показывает N первых ходов)');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 5); END;');
    DBMS_OUTPUT.PUT_LINE('     (Повторный вызов покажет следующие 5 ходов и т.д.)');
    DBMS_OUTPUT.PUT_LINE('     BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 5); END;');
    DBMS_OUTPUT.PUT_LINE('     (Сессия реплея сбрасывается через 30 мин или при вызове stop_watching)');
    DBMS_OUTPUT.PUT_LINE(c_nl);
    
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('Для повторного вывода этой справки: BEGIN game_logic.info; END;');
    DBMS_OUTPUT.PUT_LINE('================================================================');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;