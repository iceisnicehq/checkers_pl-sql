-- @function apply_move_to_board
-- @brief Simulates a move and returns the new board state as a string.
-- @dependencies:
--   - p_init_board_map (procedure)
--   - p_audit_log (procedure)
--   - c_empty_field, c_white_man, c_black_man, c_white_king, c_black_king (constants)
--   - g_map_by_idx (global variable)
--   - r_move (type)

FUNCTION apply_move_to_board(
    p_board IN VARCHAR2,
    p_move  IN r_move,
    p_color IN CHAR
) RETURN VARCHAR2 IS
    v_new_board    VARCHAR2(128) := p_board; -- Было 200 -> Стало 128
    v_moving_piece CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
    v_start_pos    PLS_INTEGER := p_move.path(1).start_idx;
    v_end_pos      PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
    v_promoted     BOOLEAN := FALSE;
    
    v_total_squares PLS_INTEGER;
    v_board_size    PLS_INTEGER;
BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    p_init_board_map(v_board_size);

    -- Очистка старой позиции
    v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

    -- Удаление срубленных шашек
    IF p_move.is_capture = 'Y' THEN
        FOR i IN 1..p_move.path.COUNT LOOP
            v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
        END LOOP;
    END IF;

    -- Превращение в дамку
    IF v_moving_piece IN (c_white_man, c_black_man) THEN
        DECLARE
            v_end_row PLS_INTEGER := g_map_by_idx(v_end_pos).row_num;
            v_is_promotion BOOLEAN := (p_color = 'W' AND v_end_row = v_board_size) OR (p_color = 'B' AND v_end_row = 1);
        BEGIN
            IF v_is_promotion THEN
                v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
            END IF;
        END;
    END IF;

    -- Установка фигуры на новое место
    v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
    RETURN v_new_board;
    
EXCEPTION
    WHEN OTHERS THEN
        p_audit_log(NULL, NULL, 'apply_move_to_board: Error ' || SQLERRM);
        RETURN p_board; 
END apply_move_to_board;