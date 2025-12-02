FUNCTION f_move_to_notation(
    p_move      IN r_move,
    p_board_size IN PLS_INTEGER
) RETURN VARCHAR2 IS
    v_notation VARCHAR2(100);
BEGIN
    IF p_move.path IS NULL OR p_move.path.COUNT = 0 THEN
        RETURN NULL;
    END IF;

    p_init_board_map(p_board_size);

    v_notation := g_map_by_idx(p_move.path(1).start_idx).notation;

    FOR j IN 1 .. p_move.path.COUNT LOOP
        v_notation := v_notation || CASE p_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                      || g_map_by_idx(p_move.path(j).end_idx).notation;
    END LOOP;
    
    RETURN v_notation;
END f_move_to_notation;