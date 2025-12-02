FUNCTION f_get_current_board_position(
    p_game_id IN NUMBER,
    p_rule_id IN NUMBER
) RETURN VARCHAR2 IS
    v_board_position VARCHAR2(100);
    v_is_puzzle CHAR(1);
    v_puzzle_id NUMBER;
BEGIN
    BEGIN
        SELECT decode_board(board_position) INTO v_board_position
        FROM (
            SELECT board_position
            FROM game_moves
            WHERE game_id = p_game_id
            ORDER BY move_number DESC
        )
        WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            BEGIN
                SELECT puzzle_id, puzzle_status INTO v_puzzle_id, v_is_puzzle
                FROM games
                WHERE game_id = p_game_id;

                IF v_is_puzzle = 'p' AND v_puzzle_id IS NOT NULL THEN
                    SELECT decode_board(board_position) INTO v_board_position
                    FROM puzzles
                    WHERE puzzle_id = v_puzzle_id;
                ELSE

                    v_board_position := get_initial_position(p_rule_id);
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN

                    v_board_position := get_initial_position(p_rule_id);
            END;
    END;
    
    RETURN v_board_position;
END f_get_current_board_position;