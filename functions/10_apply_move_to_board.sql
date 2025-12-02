FUNCTION apply_move_to_board(
    p_board IN VARCHAR2,
    p_move  IN r_move,
    p_color IN CHAR
) RETURN VARCHAR2 IS
    v_new_board    VARCHAR2(100) := p_board;
    v_moving_piece CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
    v_start_pos    PLS_INTEGER := p_move.path(1).start_idx;
    v_end_pos      PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
    
    v_total_squares PLS_INTEGER;
    v_board_size    PLS_INTEGER;
BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    p_init_board_map(v_board_size);

    v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

    IF p_move.is_capture = 'Y' THEN
        FOR i IN 1..p_move.path.COUNT LOOP
            v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
        END LOOP;
    END IF;

    IF v_moving_piece IN (c_white_man, c_black_man) THEN
        DECLARE
            v_promotion_row PLS_INTEGER := CASE p_color WHEN 'W' THEN v_board_size ELSE 1 END;
            v_current_row   PLS_INTEGER;
            v_rule_id       NUMBER := CASE v_board_size WHEN 8 THEN 1 ELSE 2 END;
        BEGIN
            IF v_rule_id = 1 THEN

                FOR i IN 1..p_move.path.COUNT LOOP
                    v_current_row := g_map_by_idx(p_move.path(i).end_idx).row_num;
                    IF v_current_row = v_promotion_row THEN

                        v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                        EXIT;
                    END IF;
                END LOOP;
            ELSE

                v_current_row := g_map_by_idx(v_end_pos).row_num;
                IF v_current_row = v_promotion_row THEN

                    v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                END IF;
            END IF;
        END;
    END IF;

    v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
    RETURN v_new_board;
END apply_move_to_board;