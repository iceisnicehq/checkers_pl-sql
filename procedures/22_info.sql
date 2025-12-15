PROCEDURE info(p_query IN VARCHAR2 DEFAULT NULL) IS
    v_query VARCHAR2(30) := UPPER(TRIM(p_query));
    v_show_all BOOLEAN := (v_query IS NULL OR v_query = 'ALL');
    v_show_full BOOLEAN := (v_query = 'ALL');
    v_found BOOLEAN := FALSE;
BEGIN

    IF v_query IS NULL OR v_query = '' THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle"');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Для корректной работы включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('Все команды выполняются в блоках PL/SQL: BEGIN ... END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('БЫСТРЫЙ СТАРТ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('1. Включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('2. Посмотрите справку: BEGIN game_logic.info; END;');
        DBMS_OUTPUT.PUT_LINE('3. Создайте игру против ИИ:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
        DBMS_OUTPUT.PUT_LINE('4. Посмотрите доску:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE('5. Сделайте ход:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.make_move(''c3-d4''); END;');
        DBMS_OUTPUT.PUT_LINE('6. ИИ автоматически ответит, и вы увидите обновленную доску.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ИСПОЛЬЗОВАНИЕ СПРАВКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Параметр p_query позволяет получить информацию по конкретной теме:');
        DBMS_OUTPUT.PUT_LINE('  - Имя процедуры (например, ''CREATE_GAME'') - информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('  - ''ALL'' - полная справка по всем процедурам и разделам');
        DBMS_OUTPUT.PUT_LINE('  - ''VIEWS'' - информация о представлениях (views) для статистики');
        DBMS_OUTPUT.PUT_LINE('  - ''RULES'' - правила игры (русские и международные шашки)');
        DBMS_OUTPUT.PUT_LINE('  - ''PARAMETERS'' - параметры игр (таймауты, ничьи)');
        DBMS_OUTPUT.PUT_LINE('  - ''STATUSES'' - статусы игр (O, C, A, V, D, T, R)');
        DBMS_OUTPUT.PUT_LINE('  - ''RATINGS'' - система рейтингов и сезонов');
        DBMS_OUTPUT.PUT_LINE('  - ''CONSTRAINTS'' - ограничения системы');
        DBMS_OUTPUT.PUT_LINE('  - ''INFO'' - информация о самой процедуре info');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''CREATE_GAME''); END;');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''ALL''); END;  -- Полная справка');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''VIEWS''); END;  -- Информация о представлениях');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''RULES''); END;  -- Правила игры');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        RETURN;
    END IF;

    IF v_query = 'INFO' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('INFO');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выводит справочную информацию о системе и процедурах.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_query - Запрос для получения информации (необязателен, по умолчанию NULL).');
        DBMS_OUTPUT.PUT_LINE('    Возможные значения:');
        DBMS_OUTPUT.PUT_LINE('      - NULL или пустая строка: краткая справка и быстрый старт');
        DBMS_OUTPUT.PUT_LINE('      - Имя процедуры: детальная информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('      - ''ALL'': полная справка по всем разделам');
        DBMS_OUTPUT.PUT_LINE('      - ''VIEWS'': информация о представлениях');
        DBMS_OUTPUT.PUT_LINE('      - ''RULES'': правила игры');
        DBMS_OUTPUT.PUT_LINE('      - ''PARAMETERS'': параметры игр');
        DBMS_OUTPUT.PUT_LINE('      - ''STATUSES'': статусы игр');
        DBMS_OUTPUT.PUT_LINE('      - ''RATINGS'': система рейтингов');
        DBMS_OUTPUT.PUT_LINE('      - ''CONSTRAINTS'': ограничения системы');
        DBMS_OUTPUT.PUT_LINE('      - ''INFO'': информация о процедуре info');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info; END;  -- Краткая справка');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''CREATE_GAME''); END;  -- Информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''ALL''); END;  -- Полная справка');
        RETURN;
    END IF;


    IF v_show_all OR v_query = 'CREATE_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает новую игру: PvP (против игрока), PvE (против ИИ) или Puzzle (задача).');
        IF v_show_full OR v_query = 'CREATE_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('                          NULL = открытая игра для присоединения любого игрока.');
            DBMS_OUTPUT.PUT_LINE('  p_ai_difficulty       - Сложность ИИ: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = PvP).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные) (необязателен, по умолчанию NULL = случайно).');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10) (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N'' (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id           - ID задачи для решения (необязателен, по умолчанию NULL = обычная игра).');
            DBMS_OUTPUT.PUT_LINE('  p_daily               - ''Y'' если это задача дня (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Easy):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Решение задачи:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
            DBMS_OUTPUT.PUT_LINE('  -- PvP игра с таймаутами:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_opponent_username => ''BOB'', p_time_limit_move_sec => 60); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'JOIN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('JOIN_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Присоединяет вас к открытой игре или принимает прямой вызов.');
        IF v_show_full OR v_query = 'JOIN_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id - ID игры для присоединения (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_game(p_game_id => 123); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'MAKE_MOVE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('MAKE_MOVE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выполняет ход в текущей активной игре.');
        IF v_show_full OR v_query = 'MAKE_MOVE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_move_notation - Нотация хода (обязателен).');
            DBMS_OUTPUT.PUT_LINE('    Формат: ''a3-b4'' для тихого хода, ''c3:e5'' для взятия.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3-d4''); END;  -- Тихий ход');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5''); END;  -- Взятие');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'PRINT_ACTIVE_BOARD' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('PRINT_ACTIVE_BOARD');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выводит текущее состояние доски активной игры.');
        DBMS_OUTPUT.PUT_LINE('  - Для активных игр (статус ''A''): показывает доску с информацией об игроках и текущем ходе.');
        DBMS_OUTPUT.PUT_LINE('  - Для открытых игр (статус ''O'' или ''C''):');
        DBMS_OUTPUT.PUT_LINE('    * Без wait_for_turn: выводит сообщение "К игре еще никто не подключился".');
        DBMS_OUTPUT.PUT_LINE('    * С wait_for_turn=''Y'': ждет подключения игрока, затем показывает доску.');
        IF v_show_full OR v_query = 'PRINT_ACTIVE_BOARD' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID игры (необязателен, по умолчанию NULL). Если не указан, используется ваша активная игра.');
            DBMS_OUTPUT.PUT_LINE('  p_username      - Имя пользователя для поиска его активной игры (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('  p_wait_for_turn - ''Y'' для ожидания хода/подключения, ''N'' для немедленного вывода (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE('                    Для активных игр: ждет вашего хода.');
            DBMS_OUTPUT.PUT_LINE('                    Для открытых игр: ждет подключения другого игрока.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Просмотр активной игры:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Ожидание вашего хода (для активных игр):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Проверка открытой игры (без ожидания):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Выведет: "К игре еще никто не подключился."');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Ожидание подключения к открытой игре:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Будет ждать, пока кто-то подключится, затем покажет доску.');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'RESIGN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('RESIGN_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Сдаться в текущей активной игре.');
        IF v_show_full OR v_query = 'RESIGN_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_resign_match - ''Y'' для сдачи во всем матче, ''N'' или NULL для сдачи только в текущей игре (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'CANCEL_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CANCEL_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Отменяет открытую игру или вызов.');
        IF v_show_full OR v_query = 'CANCEL_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.cancel_game; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'DRAW' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('DRAW');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Управление предложениями ничьей (только для PvP игр).');
        IF v_show_full OR v_query = 'DRAW' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_action - Действие: ''O'' (предложить), ''A'' (принять), ''C'' (отменить свое предложение) (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''O''); END;  -- Предложить ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''A''); END;  -- Принять ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''C''); END;  -- Отменить свое предложение');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'CREATE_MATCH' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_MATCH');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает матч (серию игр до N побед).');
        IF v_show_full OR v_query = 'CREATE_MATCH' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('                          NULL = открытый матч для присоединения любого игрока.');
            DBMS_OUTPUT.PUT_LINE('  p_games_to_win        - Количество игр для победы в матче (необязателен, по умолчанию 3).');
            DBMS_OUTPUT.PUT_LINE('                          Должно быть нечетным числом (best of N, где N нечетное).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные) (необязателен, по умолчанию NULL = случайно).');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10) (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N'' (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Матч с конкретным игроком:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match(p_opponent_username => ''ALICE''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Открытый матч:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Матч best of 5:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match(p_opponent_username => ''BOB'', p_games_to_win => 5, p_rule_id => 2); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'JOIN_MATCH' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('JOIN_MATCH');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Присоединяется к матчу.');
        IF v_show_full OR v_query = 'JOIN_MATCH' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_match_id - ID матча для присоединения (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_match(p_match_id => 555); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'SHOW_DAILY_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_DAILY_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает ежедневную задачу.');
        IF v_show_full OR v_query = 'SHOW_DAILY_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_daily_puzzle; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'SHOW_PUZZLES' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_PUZZLES');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает список доступных задач.');
        IF v_show_full OR v_query = 'SHOW_PUZZLES' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = все).');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id  - ID конкретной задачи для детального просмотра (необязателен, по умолчанию NULL = список всех).');
            DBMS_OUTPUT.PUT_LINE('  p_solution   - ''Y'' для показа решения (только для одной задачи по ID и только если были попытки)');
            DBMS_OUTPUT.PUT_LINE('                  (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_difficulty => ''M''); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_puzzle_id => 1, p_solution => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'SHOW_MY_PUZZLES' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_MY_PUZZLES');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает задачи, созданные вами.');
        IF v_show_full OR v_query = 'SHOW_MY_PUZZLES' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = все).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles(p_difficulty => ''H''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'CREATE_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает новую задачу из произвольной позиции.');
        IF v_show_full OR v_query = 'CREATE_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_board_position   - Позиция доски в формате RLE (Run-Length Encoding) (обязателен).');
            DBMS_OUTPUT.PUT_LINE('                          Формат: числа обозначают количество пустых клеток, буквы - фигуры.');
            DBMS_OUTPUT.PUT_LINE('                          Пример: ''16b1b4b1b6b1b3b4b6w1b1w1w4w3w1w6w6w5w12'' (доска 10x10).');
            DBMS_OUTPUT.PUT_LINE('  p_turn_to_move     - Чей ход: ''W'' (Белые) или ''B'' (Черные) (обязателен).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_solve   - Оптимальное количество ходов для решения (необязателен, по умолчанию NULL = игра с ИИ).');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty_level - Сложность: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию ''M'').');
            DBMS_OUTPUT.PUT_LINE('  p_solution         - Решение задачи в виде последовательности ходов (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Пример для доски 10x10 (ход белых):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_puzzle(');
            DBMS_OUTPUT.PUT_LINE('      p_board_position => ''16b1b4b1b6b1b3b4b6w1b1w1w4w3w1w6w6w5w12'',');
            DBMS_OUTPUT.PUT_LINE('      p_turn_to_move => ''W''');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'DELETE_MY_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('DELETE_MY_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Удаляет задачу, созданную вами.');
        IF v_show_full OR v_query = 'DELETE_MY_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id - ID задачи для удаления (обязателен). Используйте 0 для удаления всех своих задач.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(15); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(0); END; -- удалить все свои задачи');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'STOP_SPECTATING' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('STOP_SPECTATING');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выход из режима просмотра игры.');
        IF v_show_full OR v_query = 'STOP_SPECTATING' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.stop_spectating; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'WATCH_GAME_REPLAY' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Просматривает ходы завершенной игры пошагово.');
        IF v_show_full OR v_query = 'WATCH_GAME_REPLAY' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID завершенной игры (обязателен).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_show - Количество ходов для показа за один вызов (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_restart       - Начать просмотр с начала (''Y'') или продолжить (''N'') (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 3); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_restart => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_query = 'RULES' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРАВИЛА ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('РУССКИЕ ШАШКИ (rule_id = 1, доска 8x8):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно, но можно выбрать ЛЮБОЕ взятие.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('МЕЖДУНАРОДНЫЕ ШАШКИ (rule_id = 2, доска 10x10):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно МАКСИМАЛЬНОЕ количество фигур.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит при остановке на последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ОБЩИЕ ПРАВИЛА:');
        DBMS_OUTPUT.PUT_LINE('  - Белые начинают первыми.');
        DBMS_OUTPUT.PUT_LINE('  - Пат (нет ходов) = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Отсутствие фигур = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: по соглашению, по лимиту ходов без взятий, по повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'RULES' THEN RETURN; END IF;
    END IF;

    IF v_query = 'PARAMETERS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ТАЙМАУТЫ:');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_move_sec: Лимит времени на один ход (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Если время истекает, игрок проигрывает (статус ''T'' - Timeout).');
        DBMS_OUTPUT.PUT_LINE('    Джоб таймаута создается при join_game и переносится при каждом ходе.');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 30 секунд.');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_game_sec: Лимит времени на всю партию (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 600 секунд (10 минут).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('НИЧЬИ:');
        DBMS_OUTPUT.PUT_LINE('  - p_draw_moves_limit: Количество полуходов без взятий для автоматической ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Например, 15 означает, что после 15 полуходов без взятий игра заканчивается ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 5.');
        DBMS_OUTPUT.PUT_LINE('  - p_enable_pos_rep_draw: ''Y'' включает ничью по троекратному повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПРИМЕР ИГРЫ С ВСЕМИ ПАРАМЕТРАМИ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN');
        DBMS_OUTPUT.PUT_LINE('    game_logic.create_game(');
        DBMS_OUTPUT.PUT_LINE('      p_opponent_username => ''BOB'',');
        DBMS_OUTPUT.PUT_LINE('      p_player_color => ''W'',');
        DBMS_OUTPUT.PUT_LINE('      p_rule_id => 1,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_move_sec => 60,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_game_sec => 3600,');
        DBMS_OUTPUT.PUT_LINE('      p_draw_moves_limit => 15,');
        DBMS_OUTPUT.PUT_LINE('      p_enable_pos_rep_draw => ''Y''');
        DBMS_OUTPUT.PUT_LINE('    );');
        DBMS_OUTPUT.PUT_LINE('  END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'PARAMETERS' THEN RETURN; END IF;
    END IF;
        
    IF v_query = 'STATUSES' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('СТАТУСЫ ИГР');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  ''O'' - Open (Открытая, ждет соперника)');
        DBMS_OUTPUT.PUT_LINE('  ''C'' - Challenged (Вызов, ждет принятия)');
        DBMS_OUTPUT.PUT_LINE('  ''A'' - Active (Активная, идет игра)');
        DBMS_OUTPUT.PUT_LINE('  ''V'' - Victory (Победа одного из игроков)');
        DBMS_OUTPUT.PUT_LINE('  ''D'' - Draw (Ничья)');
        DBMS_OUTPUT.PUT_LINE('  ''T'' - Timeout (Таймаут)');
        DBMS_OUTPUT.PUT_LINE('  ''R'' - Resigned (Сдача)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'STATUSES' THEN RETURN; END IF;
    END IF;
        
    IF v_query = 'VIEWS' OR v_show_full THEN
        IF v_query = 'VIEWS' THEN
            v_found := TRUE;
        END IF;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ (VIEWS) ДЛЯ СТАТИСТИКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ БЕЗ ПАРАМЕТРОВ:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные игры (со статусом партии):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games WHERE game_id = 123;  -- статус конкретной игры');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_matches;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_matches;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Правила игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_rules;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ С ФИЛЬТРАМИ:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Протокол партии (все ходы со статусом):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_protocol WHERE game_id = 123 ORDER BY move_number;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Завершенные игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games WHERE match_id IS NOT NULL;  -- игры из матчей');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Завершенные матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_matches;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_matches WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Детали матча (все игры в матче):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_match_details WHERE match_id = 10 ORDER BY game_id;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока (все партии всех игроков):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE player_name = USER;  -- моя история');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE rule_id = 1;  -- русские шашки (1=русские, 2=международные)');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE start_time >= DATE ''2025-01-01'' AND end_time <= DATE ''2025-01-31'';  -- за период');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE match_id IS NOT NULL;  -- игры из матчей');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинги/топ (все игроки, все сезоны):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings WHERE season_id = 5;  -- конкретный сезон');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Результаты Daily Puzzles (только для тех, кто решал):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results WHERE player_name = USER;  -- мои результаты');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'VIEWS' THEN RETURN; END IF;
    END IF;
        
    IF v_query = 'RATINGS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('РЕЙТИНГИ И СЕЗОНЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Начальный рейтинг нового игрока: 500 для всех правил.');
        DBMS_OUTPUT.PUT_LINE('  - Победа в обычной игре: +16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Поражение в обычной игре: -16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Решение задачи (первый раз): +5 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: рейтинг не меняется.');
        DBMS_OUTPUT.PUT_LINE('  - Минимальный рейтинг: 0 (не может быть отрицательным).');
        DBMS_OUTPUT.PUT_LINE('  - Сезоны обновляются автоматически каждый месяц (scheduler).');
        DBMS_OUTPUT.PUT_LINE('  - Формат сезона: "Месяц-Год" (например, "Январь-2025").');
        DBMS_OUTPUT.PUT_LINE('  - При создании нового сезона триггер trg_init_season_ratings автоматически');
        DBMS_OUTPUT.PUT_LINE('    создает рейтинги для всех игроков по формуле: rating * 0.8 (минимум 500).');
        DBMS_OUTPUT.PUT_LINE('    Если рейтинг < 500, он остается 500.');
        DBMS_OUTPUT.PUT_LINE('  - Матч: +16 за победу в игре, -16 за поражение, +10*N бонус за матч (N = games_to_win)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'RATINGS' THEN RETURN; END IF;
    END IF;
        
    IF v_query = 'CONSTRAINTS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОГРАНИЧЕНИЯ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Один пользователь может иметь только одну активную сессию.');
        DBMS_OUTPUT.PUT_LINE('  - Активная сессия = игра (статус ''A'', ''O'', ''C'') или просмотр (spectating).');
        DBMS_OUTPUT.PUT_LINE('  - При попытке создать вторую игру будет ошибка.');
        DBMS_OUTPUT.PUT_LINE('  - Длительное простаивание автоматически завершает сессию (scheduler, 24 часа).');
        DBMS_OUTPUT.PUT_LINE('  - Лимит времени на ход: минимум 30 секунд.');
        DBMS_OUTPUT.PUT_LINE('  - Лимит времени на партию: минимум 600 секунд (10 минут).');
        DBMS_OUTPUT.PUT_LINE('  - Лимит полуходов без взятий: минимум 5.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'CONSTRAINTS' THEN RETURN; END IF;
    END IF;

    IF NOT v_show_all AND NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: Процедура или запрос "' || v_query || '" не найден.');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('Доступные запросы: ALL (полная справка), VIEWS, RULES, PARAMETERS, STATUSES, RATINGS, CONSTRAINTS, INFO');
        DBMS_OUTPUT.PUT_LINE('Для полной справки: BEGIN game_logic.info(p_query => ''ALL''); END;');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;