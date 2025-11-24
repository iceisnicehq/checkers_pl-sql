-- @procedure show_my_puzzles
-- @brief Shows a list of puzzles created by the current user.
-- @dependencies:
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - f_get_board_as_clob (function)

PROCEDURE show_my_puzzles(p_difficulty IN NUMBER DEFAULT NULL) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_visual_board CLOB;
    v_goal_str  VARCHAR2(50);
    
    CURSOR c_my_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            puz.board_position,
            puz.turn_to_move,
            puz.end_condition
        FROM puzzles puz
        WHERE 
            puz.created_by_player_id = v_player_id
            AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty)
        ORDER BY puz.puzzle_id DESC; -- Новые сверху
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    DBMS_OUTPUT.PUT_LINE('==================================================');
    DBMS_OUTPUT.PUT_LINE('              МОИ СОЗДАННЫЕ ЗАДАЧИ');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('           (Фильтр по Сложности: ' || p_difficulty || ')');
    END IF;
    DBMS_OUTPUT.PUT_LINE('==================================================');

    FOR r IN c_my_puzzles LOOP
        v_found := TRUE;
        
        v_goal_str := CASE r.end_condition 
                        WHEN 'D' THEN 'Ничья' 
                        ELSE 'Победа' 
                      END;

        DBMS_OUTPUT.PUT_LINE('ID: ' || r.puzzle_id || ' | Сложность: ' || r.difficulty_level || ' | Цель: ' || v_goal_str || ' за ' || NVL(TO_CHAR(r.moves_to_solve), '?') || ' ход(ов)');
        DBMS_OUTPUT.PUT_LINE('Первый ход: ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);
        
        -- Визуализация
        v_visual_board := f_get_board_as_clob(r.board_position);
        DBMS_OUTPUT.PUT_LINE(v_visual_board);
        DBMS_OUTPUT.PUT_LINE('__________________________________________________'); -- Разделитель
        DBMS_OUTPUT.PUT_LINE(''); -- Пустая строка для отступа
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... У вас нет созданных задач' || 
            CASE WHEN p_difficulty IS NOT NULL THEN ' с заданной сложностью' ELSE '' END || '. ...');
    END IF;
END show_my_puzzles;