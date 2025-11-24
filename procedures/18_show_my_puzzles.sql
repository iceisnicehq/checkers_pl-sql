-- @procedure show_my_puzzles
-- @brief Shows a list of puzzles created by the current user.
-- @dependencies:
--   - puzzles (table)
--   - get_or_create_player_id (function)

PROCEDURE show_my_puzzles(p_difficulty IN NUMBER DEFAULT NULL) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    
    CURSOR c_my_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            puz.board_position,
            puz.turn_to_move
        FROM puzzles puz
        WHERE 
            puz.created_by_player_id = v_player_id
            AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    DBMS_OUTPUT.PUT_LINE('--- Мои Созданные Задачи ---');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(' (Фильтр по Сложности: ' || p_difficulty || ')');
    END IF;

    DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || RPAD('Сложность', 10) || RPAD('Ходов', 6) || RPAD('Ход', 4) || 'Позиция (RLE)');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 5, '-') || ' ' || RPAD('-', 10, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

    FOR r IN c_my_puzzles LOOP
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.puzzle_id, 5) || 
            RPAD(r.difficulty_level, 10) || 
            RPAD(NVL(TO_CHAR(r.moves_to_solve), 'N/A'), 6) || 
            RPAD(r.turn_to_move, 4) || 
            r.board_position
        );
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... У вас нет созданных задач' || 
            CASE WHEN p_difficulty IS NOT NULL THEN ' (Сложность: ' || p_difficulty || ')' ELSE '' END || '. ...');
    END IF;
END show_my_puzzles;