FUNCTION idx_to_notation(
    p_idx IN PLS_INTEGER, 
    p_board_size IN NUMBER
) RETURN VARCHAR2 IS
BEGIN
    p_init_board_map(p_board_size); 
    
    RETURN g_map_by_idx(p_idx).notation;
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END idx_to_notation;
