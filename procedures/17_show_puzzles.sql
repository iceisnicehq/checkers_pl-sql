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
    
    CURSOR c_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            NVL(pl.username, 'System') AS creator_username,
            puz.board_position,
            puz.turn_to_move
        FROM puzzles puz
        LEFT JOIN players pl ON puz.created_by_player_id = pl.player_id
        WHERE 
            (p_puzzle_id IS NOT NULL AND puz.puzzle_id = p_puzzle_id)
            OR 
            (p_puzzle_id IS NULL AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty));
BEGIN
    v_player_id := get_or_create_player_id(USER);

    DBMS_OUTPUT.PUT_LINE('--- Список Задач ---');
    
    IF p_puzzle_id IS NOT NULL THEN
        v_header := ' (Поиск по ID: ' || p_puzzle_id || ')';
    ELSIF p_difficulty IS NOT NULL THEN
        v_header := ' (Фильтр по Сложности: ' || p_difficulty || ')';
    ELSE
        v_header := ' (Все задачи)';
    END IF;
    DBMS_OUTPUT.PUT_LINE(v_header);
    
    DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || RPAD('Сложность', 10) || RPAD('Ходов', 6) || RPAD('Автор', 15) || RPAD('Ход', 4) || 'Позиция (RLE)');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 5, '-') || ' ' || RPAD('-', 10, '-') || ' ' || RPAD('-', 6, '-') || ' ' || RPAD('-', 15, '-') || ' ' || RPAD('-', 4, '-') || ' ' || RPAD('-', 20, '-'));

    FOR r IN c_puzzles LOOP
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.puzzle_id, 5) || 
            RPAD(r.difficulty_level, 10) || 
            RPAD(NVL(TO_CHAR(r.moves_to_solve), 'N/A'), 6) || 
            RPAD(r.creator_username, 15) || 
            RPAD(r.turn_to_move, 4) || 
            r.board_position
        );
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... Задачи, соответствующие критериям, не найдены. ...');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при показе задач: ' || SQLERRM);
END show_puzzles;