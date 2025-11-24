-- @procedure show_puzzles
-- @brief Shows a list of available puzzles.
-- @dependencies:
--   - puzzles (table)
--   - players (table)
--   - get_or_create_player_id (function)

PROCEDURE show_puzzles(
    p_difficulty IN NUMBER DEFAULT NULL, 
    p_puzzle_id  IN NUMBER DEFAULT NULL
) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_header    VARCHAR2(200);
    v_goal_str  VARCHAR2(50);
    v_visual_board CLOB;
    
    CURSOR c_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            NVL(pl.username, 'System') AS creator_username,
            puz.board_position,
            puz.turn_to_move,
            puz.end_condition
        FROM puzzles puz
        LEFT JOIN players pl ON puz.created_by_player_id = pl.player_id
        WHERE 
            (p_puzzle_id IS NOT NULL AND puz.puzzle_id = p_puzzle_id)
            OR 
            (p_puzzle_id IS NULL AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty))
        ORDER BY puz.puzzle_id;
BEGIN
    v_player_id := get_or_create_player_id(USER);

    -- ВАРИАНТ 1: Поиск конкретной задачи (Красивый вывод)
    IF p_puzzle_id IS NOT NULL THEN
        FOR r IN c_puzzles LOOP
            v_found := TRUE;
            v_goal_str := CASE r.end_condition WHEN 'D' THEN 'Ничья' ELSE 'Победа' END;
            
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE('ЗАДАЧА ID: ' || r.puzzle_id);
            DBMS_OUTPUT.PUT_LINE('Автор:     ' || r.creator_username);
            DBMS_OUTPUT.PUT_LINE('Сложность: ' || r.difficulty_level);
            DBMS_OUTPUT.PUT_LINE('Цель:      ' || v_goal_str || ' за ' || NVL(TO_CHAR(r.moves_to_solve), '?') || ' ход(ов)');
            DBMS_OUTPUT.PUT_LINE('Ваш ход:   ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);
            DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
            
            v_visual_board := f_get_board_as_clob(r.board_position);
            DBMS_OUTPUT.PUT_LINE(v_visual_board);
            DBMS_OUTPUT.PUT_LINE('==================================================');
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('Задача с ID ' || p_puzzle_id || ' не найдена.');
        END IF;
        RETURN;
    END IF;

    -- ВАРИАНТ 2: Общий список (Табличный вывод)
    DBMS_OUTPUT.PUT_LINE('--- Список Доступных Задач ---');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(' (Фильтр по Сложности: ' || p_difficulty || ')');
    ELSE
        DBMS_OUTPUT.PUT_LINE(' (Все задачи)');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 6) || 
        RPAD('Слож.', 6) || 
        RPAD('Ходов', 6) || 
        RPAD('Цель', 7) || 
        RPAD('Автор', 15) || 
        RPAD('Ход', 4) || 
        'Позиция (RLE)'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 6, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 7, '-') || ' ' || RPAD('-', 15, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

    FOR r IN c_puzzles LOOP
        v_found := TRUE;
        v_goal_str := CASE r.end_condition WHEN 'D' THEN 'Ничья' ELSE 'Победа' END;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.puzzle_id, 6) || 
            RPAD(r.difficulty_level, 6) || 
            RPAD(NVL(TO_CHAR(r.moves_to_solve), '?'), 6) || 
            RPAD(SUBSTR(v_goal_str, 1, 6), 7) ||
            RPAD(SUBSTR(r.creator_username, 1, 14), 15) || 
            RPAD(r.turn_to_move, 4) || 
            SUBSTR(r.board_position, 1, 25) || (CASE WHEN LENGTH(r.board_position) > 25 THEN '...' ELSE '' END)
        );
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... Задачи не найдены. ...');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при показе задач: ' || SQLERRM);
END show_puzzles;