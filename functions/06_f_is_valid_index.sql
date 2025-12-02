FUNCTION f_is_valid_index(
    p_idx           IN PLS_INTEGER,
    p_total_squares IN PLS_INTEGER,
    p_start_col     IN PLS_INTEGER,
    p_expected_col_diff IN PLS_INTEGER
) RETURN BOOLEAN IS
BEGIN
    RETURN p_idx BETWEEN 1 AND p_total_squares
       AND g_map_by_idx.EXISTS(p_idx)
       AND ABS(p_start_col - g_map_by_idx(p_idx).col_num) = p_expected_col_diff;
END f_is_valid_index;