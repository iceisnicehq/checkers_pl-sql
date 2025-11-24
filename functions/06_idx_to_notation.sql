-- @function idx_to_notation
-- @brief Converts a board index to its notation (e.g., 1 -> 'a1').
-- @dependencies:
--   - p_init_board_map (procedure)
--   - g_map_by_idx (global variable)

FUNCTION idx_to_notation(
    p_idx IN PLS_INTEGER, 
    p_board_size IN NUMBER -- <-- НОВЫЙ ПАРАМЕТР
) RETURN VARCHAR2 IS
BEGIN
    -- 1. Убедиться, что кэш нужного размера загружен
    p_init_board_map(p_board_size); 
    
    -- 2. Мгновенно получить нотацию из кэша по индексу
    RETURN g_map_by_idx(p_idx).notation;
    
EXCEPTION
    -- Если индекса нет (например, p_idx = 101), вернуть NULL
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END idx_to_notation;