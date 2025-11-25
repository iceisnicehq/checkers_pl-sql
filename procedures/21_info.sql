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
    DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Для корректной работы включите вывод: SET SERVEROUTPUT ON;');
    DBMS_OUTPUT.PUT_LINE('Все команды выполняются в блоках PL/SQL: BEGIN ... END;');
    DBMS_OUTPUT.PUT_LINE('---');
    
    DBMS_OUTPUT.PUT_LINE('## 1. СОЗДАНИЕ ИГРЫ (CREATE_GAME)');
    DBMS_OUTPUT.PUT_LINE('---------------------------------');
    DBMS_OUTPUT.PUT_LINE('>> Игра против ИИ (PvE):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_ai_difficulty => ''E'', p_player_color => ''W''); END;');
    DBMS_OUTPUT.PUT_LINE('   * Сложность: ''E'' (Легко), ''M'' (Средне), ''H'' (Сложно).');
    DBMS_OUTPUT.PUT_LINE('   * Цвет: ''W'' (Белые), ''B'' (Черные). Если NULL - случайно.');
    DBMS_OUTPUT.PUT_LINE('   * Правила: p_rule_id => 1 (Русские 8x8), 2 (Международные 10x10). По умолчанию 1.');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Открытая игра (PvP - Ждать соперника):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game; END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Прямой вызов (PvP - Конкретному игроку):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_opponent_username => ''BOB''); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 2. ПРИСОЕДИНЕНИЕ (JOIN_GAME)');
    DBMS_OUTPUT.PUT_LINE('-------------------------------');
    DBMS_OUTPUT.PUT_LINE('Если вы увидели ID открытой игры или получили вызов:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.join_game(p_game_id => 123); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 3. ИГРОВОЙ ПРОЦЕСС (ХОДЫ)');
    DBMS_OUTPUT.PUT_LINE('----------------------------');
    DBMS_OUTPUT.PUT_LINE('>> Сделать ход:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.make_move(''c3-d4''); END;');
    DBMS_OUTPUT.PUT_LINE('   * Тихий ход: ''a3-b4''');
    DBMS_OUTPUT.PUT_LINE('   * Взятие:    ''c3:e5'' (двоеточие обязательно!)');
    DBMS_OUTPUT.PUT_LINE('   * Цепочка:   ''c3:e5:g7''');
    DBMS_OUTPUT.PUT_LINE('   ВАЖНО: В Русских шашках (Rule 1) бить обязательно, но можно выбрать любой бой.');
    DBMS_OUTPUT.PUT_LINE('          В Международных (Rule 2) бить обязательно МАКСИМАЛЬНОЕ количество фигур.');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Посмотреть доску (если потеряли вывод):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.print_active_board; END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 4. УПРАВЛЕНИЕ ИГРОЙ');
    DBMS_OUTPUT.PUT_LINE('----------------------');
    DBMS_OUTPUT.PUT_LINE('>> Сдаться (Поражение):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.resign_game; END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Отменить игру (Если она еще не началась, статус ''O'' или ''C''):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.cancel_game; END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Ничья (Предложить / Принять / Отклонить):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.draw(''O''); END; -- (O)ffer');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.draw(''A''); END; -- (A)ccept');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.draw(''C''); END; -- (C)ancel / Decline');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 5. МАТЧИ (СЕРИИ ИГР)');
    DBMS_OUTPUT.PUT_LINE('-----------------------');
    DBMS_OUTPUT.PUT_LINE('Матч - это серия игр до N побед с одним соперником.');
    DBMS_OUTPUT.PUT_LINE('>> Создать матч:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_match(p_opponent_username => ''ALICE'', p_games_to_win => 3); END;');
    DBMS_OUTPUT.PUT_LINE('>> Присоединиться к матчу:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.join_match(p_match_id => 555); END;');
    DBMS_OUTPUT.PUT_LINE('>> Сдаться во всем матче:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);
    
    DBMS_OUTPUT.PUT_LINE('## 6. ЗАДАЧИ И ГОЛОВОЛОМКИ (PUZZLES)');
    DBMS_OUTPUT.PUT_LINE('------------------------------------');
    DBMS_OUTPUT.PUT_LINE('>> ЗАДАЧА ДНЯ (Ежедневный челлендж):');
    DBMS_OUTPUT.PUT_LINE('   Посмотреть: BEGIN game_logic.show_daily_puzzle; END;');
    DBMS_OUTPUT.PUT_LINE('   Решать:     BEGIN game_logic.start_daily_puzzle; END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Список всех задач:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.show_puzzles; END; -- Таблица всех задач');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.show_puzzles(p_difficulty => 1); END; -- Фильтр (0=Easy, 1=Medium, 2=Hard)');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.show_puzzles(p_puzzle_id => 10); END; -- Детальный просмотр ID 10 (с графикой)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Решать конкретную задачу:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Создать свою задачу (RLE-строка):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_puzzle(p_board_position => ''...'', p_turn_to_move => ''W'', p_moves_to_solve => 3); END;');
    DBMS_OUTPUT.PUT_LINE('>> Мои задачи (управление):');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.show_my_puzzles; END;');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.delete_my_puzzle(15); END;');
    DBMS_OUTPUT.PUT_LINE(c_nl);

    DBMS_OUTPUT.PUT_LINE('## 7. РЕЖИМ ЗРИТЕЛЯ');
    DBMS_OUTPUT.PUT_LINE('-------------------');
    DBMS_OUTPUT.PUT_LINE('>> Смотреть активную игру:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.print_active_board(p_username => ''GARRY''); END;');
    DBMS_OUTPUT.PUT_LINE('   * Можно использовать p_wait_for_turn => ''Y'' для ожидания хода.');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Выйти из режима зрителя:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.stop_spectating; END;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('>> Смотреть повтор завершенной игры:');
    DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 5); END;');
    DBMS_OUTPUT.PUT_LINE('   (Вызывайте повторно, чтобы листать ходы вперед)');
    DBMS_OUTPUT.PUT_LINE(c_nl);
    
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('Рейтинг: Победа +16, Поражение -16, Пазл +5 (первый раз).');
    DBMS_OUTPUT.PUT_LINE('Удачи!');
    DBMS_OUTPUT.PUT_LINE('================================================================');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;