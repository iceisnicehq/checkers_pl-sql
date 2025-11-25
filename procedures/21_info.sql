-- @procedure info
-- @brief Displays help information about the game_logic package.
-- @dependencies:
--   - (none)

PROCEDURE info(p_proc_name IN VARCHAR2 DEFAULT NULL) IS
    c_nl CONSTANT VARCHAR2(1) := CHR(10);
    v_proc_name VARCHAR2(100) := UPPER(TRIM(p_proc_name));
    v_show_all BOOLEAN := (v_proc_name IS NULL OR v_proc_name = '');
    v_found BOOLEAN := FALSE;
BEGIN
    -- Если параметр не передан, показываем подсказку в начале
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle" (v1.2)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Для корректной работы включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('Все команды выполняются в блоках PL/SQL: BEGIN ... END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПОДСКАЗКА: Для просмотра информации по конкретной процедуре передайте параметр:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_proc_name => ''CREATE_GAME''); END;');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE(c_nl);
    END IF;
    
    -- Секция 1: CREATE_GAME
    IF v_show_all OR v_proc_name = 'CREATE_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 1. СОЗДАНИЕ ИГРЫ (CREATE_GAME)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Создает новую игру: PvP (против игрока), PvE (против ИИ) или Puzzle (задача).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (PvP). NULL = открытая игра.');
        DBMS_OUTPUT.PUT_LINE('  p_ai_difficulty       - Сложность ИИ: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard). NULL = PvP.');
        DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные). NULL = случайно.');
        DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10). По умолчанию 1.');
        DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей. NULL = без лимита.');
        DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N''. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE('  p_puzzle_id           - ID задачи для решения. NULL = обычная игра.');
        DBMS_OUTPUT.PUT_LINE('  p_daily               - ''Y'' если это задача дня. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Легко, Русские шашки):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_ai_difficulty => ''E'', p_player_color => ''W''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Сложно, Международные 10x10, с таймаутами):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN');
        DBMS_OUTPUT.PUT_LINE('    game_logic.create_game(');
        DBMS_OUTPUT.PUT_LINE('      p_ai_difficulty => ''H'',');
        DBMS_OUTPUT.PUT_LINE('      p_rule_id => 2,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_move_sec => 120,');
        DBMS_OUTPUT.PUT_LINE('      p_draw_moves_limit => 25');
        DBMS_OUTPUT.PUT_LINE('    );');
        DBMS_OUTPUT.PUT_LINE('  END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытая игра (ждет любого соперника):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game; END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Прямой вызов конкретному игроку:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_opponent_username => ''BOB'', p_player_color => ''W''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Решение задачи:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 2: JOIN_GAME
    IF v_show_all OR v_proc_name = 'JOIN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 2. ПРИСОЕДИНЕНИЕ К ИГРЕ (JOIN_GAME)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Присоединяет вас к открытой игре или принимает прямой вызов.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_game_id - ID игры для присоединения.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_game(p_game_id => 123); END;');
        DBMS_OUTPUT.PUT_LINE('  -- После присоединения игра становится активной (статус ''A'')');
        DBMS_OUTPUT.PUT_LINE('  -- и создается джоб таймаута хода (если задан p_time_limit_move_sec)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 3: MAKE_MOVE
    IF v_show_all OR v_proc_name = 'MAKE_MOVE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 3. ХОДЫ (MAKE_MOVE)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Выполняет ход в текущей активной игре.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_move_notation - Нотация хода в формате: начальная-конечная или начальная:конечная');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ФОРМАТ НОТАЦИИ:');
        DBMS_OUTPUT.PUT_LINE('  - Тихий ход: ''a3-b4'' (дефис между полями)');
        DBMS_OUTPUT.PUT_LINE('  - Взятие:    ''c3:e5'' (двоеточие между полями)');
        DBMS_OUTPUT.PUT_LINE('  - Цепочка:   ''c3:e5:g7'' (множественные взятия)');
        DBMS_OUTPUT.PUT_LINE('  - Для 10x10: ''a1-b2'', ''j10:i9:h8'' и т.д.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРАВИЛА ВЗЯТИЙ:');
        DBMS_OUTPUT.PUT_LINE('  - Русские шашки (rule_id=1): Взятие обязательно, можно выбрать ЛЮБОЕ взятие.');
        DBMS_OUTPUT.PUT_LINE('  - Международные (rule_id=2): Взятие обязательно МАКСИМАЛЬНОЕ количество фигур.');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка бьет вперед и назад.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет на любое расстояние с произвольным приземлением.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3-d4''); END;  -- Тихий ход');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5''); END;  -- Взятие');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5:g7''); END; -- Цепочка взятий');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПОСЛЕ ХОДА:');
        DBMS_OUTPUT.PUT_LINE('  - Если игра против ИИ, ИИ автоматически делает ответный ход.');
        DBMS_OUTPUT.PUT_LINE('  - Таймаут хода переносится на следующий ход.');
        DBMS_OUTPUT.PUT_LINE('  - Проверяется окончание игры (победа, ничья, пат).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 4: PRINT_ACTIVE_BOARD
    IF v_show_all OR v_proc_name = 'PRINT_ACTIVE_BOARD' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 4. ПРОСМОТР ДОСКИ (PRINT_ACTIVE_BOARD)');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Выводит текущее состояние доски активной игры.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID игры для просмотра. NULL = ваша текущая игра.');
        DBMS_OUTPUT.PUT_LINE('  p_username      - Имя пользователя, чью игру смотреть. NULL = ваша игра.');
        DBMS_OUTPUT.PUT_LINE('  p_wait_for_turn - ''Y'' для ожидания вашего хода. По умолчанию ''N''.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр вашей текущей игры:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр конкретной игры:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_game_id => 123); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Просмотр игры другого пользователя (режим зрителя):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_username => ''GARRY''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Ожидание вашего хода (блокирует до вашей очереди или таймаута):');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    -- Секция 5: УПРАВЛЕНИЕ ИГРОЙ
    IF v_show_all OR v_proc_name = 'RESIGN_GAME' OR v_proc_name = 'CANCEL_GAME' OR v_proc_name = 'DRAW' THEN
        IF v_show_all OR v_proc_name = 'RESIGN_GAME' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 5. УПРАВЛЕНИЕ ИГРОЙ');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('5.1. СДАЧА (RESIGN_GAME)');
            DBMS_OUTPUT.PUT_LINE('------------------------');
            DBMS_OUTPUT.PUT_LINE('Сдаться в текущей активной игре.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_resign_match - ''Y'' для сдачи во всем матче. По умолчанию ''N''.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game; END;  -- Сдача в текущей игре');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;  -- Сдача во всем матче');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'CANCEL_GAME' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('5.2. ОТМЕНА ИГРЫ (CANCEL_GAME)');
            DBMS_OUTPUT.PUT_LINE('------------------------------');
            DBMS_OUTPUT.PUT_LINE('Отменяет открытую игру (статус ''O'') или вызов (статус ''C'').');
            DBMS_OUTPUT.PUT_LINE('Нельзя отменить активную игру - используйте resign_game.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.cancel_game; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'DRAW' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('5.3. НИЧЬЯ (DRAW)');
            DBMS_OUTPUT.PUT_LINE('-----------------');
            DBMS_OUTPUT.PUT_LINE('Управление предложениями ничьей (только для PvP игр, не для PvE).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_action - Действие: ''O'' (Offer - предложить), ''A'' (Accept - принять), ''C'' (Cancel/Decline - отменить/отклонить)');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''O''); END;  -- Предложить ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''A''); END;  -- Принять предложение оппонента');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''C''); END;  -- Отменить свое или отклонить чужое предложение');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('АВТОМАТИЧЕСКИЕ НИЧЬИ:');
            DBMS_OUTPUT.PUT_LINE('  - По лимиту ходов без взятий (если задан p_draw_moves_limit)');
            DBMS_OUTPUT.PUT_LINE('  - По повтору позиции (если p_enable_pos_rep_draw = ''Y'')');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 6: МАТЧИ
    IF v_show_all OR v_proc_name = 'CREATE_MATCH' OR v_proc_name = 'JOIN_MATCH' THEN
        IF v_show_all OR v_proc_name = 'CREATE_MATCH' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 6. МАТЧИ (СЕРИИ ИГР)');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('Матч - это серия игр до N побед с одним соперником (best-of-N).');
            DBMS_OUTPUT.PUT_LINE('Цвета чередуются в каждой игре матча.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('6.1. СОЗДАНИЕ МАТЧА (CREATE_MATCH)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента (обязательно).');
            DBMS_OUTPUT.PUT_LINE('  p_games_to_win        - Количество побед для победы в матче (обязательно, > 0).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет в первой игре: ''W''/''B''. NULL = случайно.');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (8x8) или 2 (10x10). По умолчанию 1.');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах.');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на партию в секундах.');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей.');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N''.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_match(');
            DBMS_OUTPUT.PUT_LINE('      p_opponent_username => ''ALICE'',');
            DBMS_OUTPUT.PUT_LINE('      p_games_to_win => 3,');
            DBMS_OUTPUT.PUT_LINE('      p_player_color => ''W'',');
            DBMS_OUTPUT.PUT_LINE('      p_rule_id => 1');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'JOIN_MATCH' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('6.2. ПРИСОЕДИНЕНИЕ К МАТЧУ (JOIN_MATCH)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_match_id - ID матча для присоединения.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_match(p_match_id => 555); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 7: ЗАДАЧИ И ГОЛОВОЛОМКИ
    IF v_show_all OR v_proc_name IN ('SHOW_DAILY_PUZZLE', 'SHOW_PUZZLES', 'SHOW_MY_PUZZLES', 'CREATE_PUZZLE', 'DELETE_MY_PUZZLE') THEN
        IF v_show_all OR v_proc_name = 'SHOW_DAILY_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE('## 7. ЗАДАЧИ И ГОЛОВОЛОМКИ (PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('================================================================');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            DBMS_OUTPUT.PUT_LINE('7.1. ЗАДАЧА ДНЯ (SHOW_DAILY_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('-----------------------------------');
            DBMS_OUTPUT.PUT_LINE('Показывает ежедневную задачу (обновляется автоматически каждый день).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_daily_puzzle; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Затем для решения:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_daily => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'SHOW_PUZZLES' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.2. ПРОСМОТР ЗАДАЧ (SHOW_PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------');
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности (1, 2, 3...). NULL = все задачи.');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id  - ID конкретной задачи для детального просмотра. NULL = список всех.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles; END;  -- Список всех задач');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_difficulty => 1); END;  -- Только сложность 1');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_puzzle_id => 10); END;  -- Детальный просмотр с доской');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'SHOW_MY_PUZZLES' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.3. МОИ ЗАДАЧИ (SHOW_MY_PUZZLES)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------');
            DBMS_OUTPUT.PUT_LINE('Показывает задачи, созданные вами.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности. NULL = все ваши задачи.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'CREATE_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.4. СОЗДАНИЕ ЗАДАЧИ (CREATE_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Создает новую задачу из произвольной позиции.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_board_position   - Позиция доски в формате CLOB (многострочный текст).');
            DBMS_OUTPUT.PUT_LINE('                       Каждая строка = один ряд доски (8 или 10 символов).');
            DBMS_OUTPUT.PUT_LINE('                       Символы: ''w''/''W'' (белая простая/дамка), ''b''/''B'' (черная), ''+'' (пусто).');
            DBMS_OUTPUT.PUT_LINE('  p_turn_to_move     - Чей ход: ''W'' (Белые) или ''B'' (Черные).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_solve   - Количество ходов для решения. NULL = без ограничения.');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty_level - Уровень сложности (1, 2, 3...). По умолчанию 1.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР (8x8):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_puzzle(');
            DBMS_OUTPUT.PUT_LINE('      p_board_position => ''+b+b+b+b'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''b+b+b+b+'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''++++++++'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''+w+w+w+w'' || CHR(10) ||');
            DBMS_OUTPUT.PUT_LINE('                        ''w+w+w+w+'',');
            DBMS_OUTPUT.PUT_LINE('      p_turn_to_move => ''W'',');
            DBMS_OUTPUT.PUT_LINE('      p_moves_to_solve => 3,');
            DBMS_OUTPUT.PUT_LINE('      p_difficulty_level => 1');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'DELETE_MY_PUZZLE' THEN
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE('7.5. УДАЛЕНИЕ ЗАДАЧИ (DELETE_MY_PUZZLE)');
            DBMS_OUTPUT.PUT_LINE('---------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Удаляет задачу, созданную вами (нельзя удалить задачу, используемую в игре).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id - ID задачи для удаления.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(15); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all THEN
            DBMS_OUTPUT.PUT_LINE('7.6. РЕШЕНИЕ ЗАДАЧИ');
            DBMS_OUTPUT.PUT_LINE('-------------------');
            DBMS_OUTPUT.PUT_LINE('Для решения задачи используйте create_game с p_puzzle_id:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
            DBMS_OUTPUT.PUT_LINE('Затем делайте ходы как в обычной игре через make_move.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
        END IF;
    END IF;
    
    -- Секция 8: РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ
    IF v_show_all OR v_proc_name IN ('STOP_SPECTATING', 'WATCH_GAME_REPLAY') THEN
        IF v_show_all OR v_proc_name = 'STOP_SPECTATING' THEN
            v_found := TRUE;
            IF v_show_all THEN
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE('## 8. РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ');
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE(c_nl);
                DBMS_OUTPUT.PUT_LINE('8.1. ПРОСМОТР АКТИВНОЙ ИГРЫ (PRINT_ACTIVE_BOARD)');
                DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
                DBMS_OUTPUT.PUT_LINE('Если вы не участник игры, автоматически входите в режим зрителя.');
                DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_username => ''GARRY''); END;');
                DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_game_id => 123); END;');
                DBMS_OUTPUT.PUT_LINE(c_nl);
            END IF;
            
            DBMS_OUTPUT.PUT_LINE('8.2. ВЫХОД ИЗ РЕЖИМА ЗРИТЕЛЯ (STOP_SPECTATING)');
            DBMS_OUTPUT.PUT_LINE('-----------------------------------------------');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.stop_spectating; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
        
        IF v_show_all OR v_proc_name = 'WATCH_GAME_REPLAY' THEN
            v_found := TRUE;
            IF v_show_all THEN
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE('## 8. РЕЖИМ ЗРИТЕЛЯ И ПРОСМОТР РЕПЛЕЕВ');
                DBMS_OUTPUT.PUT_LINE('================================================================');
                DBMS_OUTPUT.PUT_LINE(c_nl);
            END IF;
            
            DBMS_OUTPUT.PUT_LINE('8.3. ПРОСМОТР РЕПЛЕЯ (WATCH_GAME_REPLAY)');
            DBMS_OUTPUT.PUT_LINE('----------------------------------------');
            DBMS_OUTPUT.PUT_LINE('Просматривает ходы завершенной игры пошагово.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID завершенной игры (статус ''V'', ''D'', ''T'', ''R'').');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_show - Количество ходов для показа за один вызов. По умолчанию 1.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕР:');
            DBMS_OUTPUT.PUT_LINE('  -- Показать первые 3 хода:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 3); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Вызывайте повторно для просмотра следующих ходов');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            
            IF NOT v_show_all THEN RETURN; END IF;
        END IF;
    END IF;
    
    -- Секция 9: ПРАВИЛА ИГРЫ (только при полном выводе)
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 9. ПРАВИЛА ИГРЫ');
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
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ОБЩИЕ ПРАВИЛА:');
        DBMS_OUTPUT.PUT_LINE('  - Белые начинают первыми.');
        DBMS_OUTPUT.PUT_LINE('  - Пат (нет ходов) = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Отсутствие фигур = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: по соглашению, по лимиту ходов без взятий, по повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
    END IF;
    
    -- Секции 10-15: Общая информация (только при полном выводе)
    IF v_show_all THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 10. ПАРАМЕТРЫ ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ТАЙМАУТЫ:');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_move_sec: Лимит времени на один ход (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Если время истекает, игрок проигрывает (статус ''T'' - Timeout).');
        DBMS_OUTPUT.PUT_LINE('    Джоб таймаута создается при join_game и переносится при каждом ходе.');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_game_sec: Лимит времени на всю партию (в секундах).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('НИЧЬИ:');
        DBMS_OUTPUT.PUT_LINE('  - p_draw_moves_limit: Количество полуходов без взятий для автоматической ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Например, 15 означает, что после 15 полуходов без взятий игра заканчивается ничьей.');
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
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 11. СТАТУСЫ ИГР');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  ''O'' - Open (Открытая, ждет соперника)');
        DBMS_OUTPUT.PUT_LINE('  ''C'' - Challenged (Вызов, ждет принятия)');
        DBMS_OUTPUT.PUT_LINE('  ''A'' - Active (Активная, идет игра)');
        DBMS_OUTPUT.PUT_LINE('  ''V'' - Victory (Победа одного из игроков)');
        DBMS_OUTPUT.PUT_LINE('  ''D'' - Draw (Ничья)');
        DBMS_OUTPUT.PUT_LINE('  ''T'' - Timeout (Таймаут)');
        DBMS_OUTPUT.PUT_LINE('  ''R'' - Resigned (Сдача)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 12. ПРЕДСТАВЛЕНИЯ (VIEWS) ДЛЯ СТАТИСТИКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Используйте SQL запросы для просмотра статистики:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Статус игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_status WHERE game_id = 123;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Протокол игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_protocol WHERE game_id = 123 ORDER BY move_number;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока за период:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history_by_period;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Статистика игрока:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_stats;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинг по успеху:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_leaderboard;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинг по среднему числу ходов:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_leaderboard_by_avg_moves;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Результаты Daily Puzzles:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 13. РЕЙТИНГИ И СЕЗОНЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Начальный рейтинг нового игрока: 500 для всех правил.');
        DBMS_OUTPUT.PUT_LINE('  - Победа в обычной игре: +16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Поражение в обычной игре: -16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Решение задачи (первый раз): +5 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: рейтинг не меняется.');
        DBMS_OUTPUT.PUT_LINE('  - Минимальный рейтинг: 0 (не может быть отрицательным).');
        DBMS_OUTPUT.PUT_LINE('  - Сезоны обновляются автоматически каждый месяц (scheduler).');
        DBMS_OUTPUT.PUT_LINE('  - Формат сезона: "Месяц-Год" (например, "Январь-2025").');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 14. ОГРАНИЧЕНИЯ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Один пользователь может иметь только одну активную сессию.');
        DBMS_OUTPUT.PUT_LINE('  - Активная сессия = игра (статус ''A'', ''O'', ''C'') или просмотр (spectating).');
        DBMS_OUTPUT.PUT_LINE('  - При попытке создать вторую игру будет ошибка.');
        DBMS_OUTPUT.PUT_LINE('  - Длительное простаивание автоматически завершает сессию (scheduler).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('## 15. БЫСТРЫЙ СТАРТ');
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
        DBMS_OUTPUT.PUT_LINE('Рейтинг: Победа +16, Поражение -16, Пазл +5 (первый раз).');
        DBMS_OUTPUT.PUT_LINE('Удачи в игре!');
        DBMS_OUTPUT.PUT_LINE('================================================================');
    END IF;
    
    -- Если процедура не найдена, выводим сообщение
    IF NOT v_show_all AND NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: Процедура "' || v_proc_name || '" не найдена.');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('Для полной справки: BEGIN game_logic.info; END;');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;