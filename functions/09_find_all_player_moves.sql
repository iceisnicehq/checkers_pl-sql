FUNCTION find_all_player_moves(
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_rule_id      IN NUMBER
) RETURN t_move_list IS
    v_all_moves       t_move_list := t_move_list();
    v_capture_moves   t_move_list := t_move_list();
    v_simple_moves    t_move_list := t_move_list();
    v_player_man      CHAR(1);
    v_player_king     CHAR(1);
    v_max_captures    PLS_INTEGER := 0;
    v_decoded_board   VARCHAR2(100) := decode_board(p_board);
    
    v_rule            game_rules%ROWTYPE;
    v_board_size      PLS_INTEGER;
    v_total_squares   PLS_INTEGER;
    v_simple_move_w   SYS.ODCINUMBERLIST;
    v_simple_move_b   SYS.ODCINUMBERLIST;
    v_simple_move_all SYS.ODCINUMBERLIST;
    v_max_king_range  PLS_INTEGER;
    v_simple_directions SYS.ODCINUMBERLIST;

BEGIN

    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_max_king_range  := v_board_size - 1;
        
        p_init_board_map(v_board_size);
        
        IF v_board_size = 8 THEN
            v_simple_move_w   := SYS.ODCINUMBERLIST(-9, -7);
            v_simple_move_b   := SYS.ODCINUMBERLIST(7, 9);
            v_simple_move_all := SYS.ODCINUMBERLIST(-9, -7, 7, 9);
        ELSE
            v_simple_move_w   := SYS.ODCINUMBERLIST(-11, -9);
            v_simple_move_b   := SYS.ODCINUMBERLIST(9, 11);
            v_simple_move_all := SYS.ODCINUMBERLIST(-11, -9, 9, 11);
        END IF;
    END;

    IF p_player_color = 'W' THEN
        v_player_man  := c_white_man;
        v_player_king := c_white_king;
        v_simple_directions := v_simple_move_w;
    ELSE
        v_player_man  := c_black_man;
        v_player_king := c_black_king;
        v_simple_directions := v_simple_move_b;
    END IF;

    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece       CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_start_field rec_board_field := g_map_by_idx(i);
            v_paths       t_move_list;
            v_is_king     CHAR(1);
        BEGIN

            IF v_piece IN (v_player_man, v_player_king) THEN
                v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;

                v_paths := find_capture_paths(i, v_decoded_board, p_player_color, v_is_king, p_rule_id);
                
                IF v_paths.COUNT > 0 THEN
                    FOR j IN 1 .. v_paths.COUNT LOOP
                        v_capture_moves.EXTEND;
                        v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                        IF v_paths(j).capture_count > v_max_captures THEN
                            v_max_captures := v_paths(j).capture_count;
                        END IF;
                    END LOOP;
                END IF;

                IF v_capture_moves.COUNT = 0 THEN
                    IF v_piece = v_player_man THEN

                        FOR d IN 1 .. v_simple_directions.COUNT LOOP
                            DECLARE
                                v_end_idx   PLS_INTEGER := i + v_simple_directions(d);
                                v_end_field rec_board_field;
                            BEGIN

                                IF v_end_idx BETWEEN 1 AND v_total_squares
                                   AND g_map_by_idx.EXISTS(v_end_idx)
                                   AND SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field
                                THEN
                                    v_end_field := g_map_by_idx(v_end_idx);

                                    IF ABS(v_start_field.col_num - v_end_field.col_num) = 1 THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx     := i;
                                            v_step.end_idx       := v_end_idx;
                                            v_step.captured_idx  := NULL;
                                            v_move.path          := t_move_path(v_step);
                                            v_move.is_capture    := 'N';
                                            v_move.capture_count := 0;
                                            v_simple_moves.EXTEND;
                                            v_simple_moves(v_simple_moves.LAST) := v_move;
                                        END;
                                    END IF;
                                END IF;
                            END;
                        END LOOP;
                        
                    ELSIF v_piece = v_player_king THEN

                        FOR d IN 1 .. v_simple_move_all.COUNT LOOP
                            FOR k IN 1 .. v_max_king_range LOOP 
                                DECLARE
                                    v_end_idx   PLS_INTEGER := i + (v_simple_move_all(d) * k);
                                    v_end_field rec_board_field;
                                BEGIN
                                    IF NOT g_map_by_idx.EXISTS(v_end_idx) THEN EXIT; END IF;
                                    v_end_field := g_map_by_idx(v_end_idx);

                                    IF k > 1 AND ABS(g_map_by_idx(i + (v_simple_move_all(d) * (k - 1))).col_num - v_end_field.col_num) != 1 THEN
                                        EXIT;
                                    END IF;

                                    IF SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx     := i;
                                            v_step.end_idx       := v_end_idx;
                                            v_step.captured_idx  := NULL;
                                            v_move.path          := t_move_path(v_step);
                                            v_move.is_capture    := 'N';
                                            v_move.capture_count := 0;
                                            v_simple_moves.EXTEND;
                                            v_simple_moves(v_simple_moves.LAST) := v_move;
                                        END;
                                    ELSE
                                        EXIT;
                                    END IF;
                                END;
                            END LOOP;
                        END LOOP;
                    END IF;
                END IF;
            END IF;
        END;
    END LOOP;

    IF v_capture_moves.COUNT > 0 THEN

        IF p_rule_id = 1 THEN 
            RETURN v_capture_moves;
        ELSE 

            FOR i IN 1 .. v_capture_moves.COUNT LOOP
                IF v_capture_moves(i).capture_count = v_max_captures THEN
                    v_all_moves.EXTEND;
                    v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                END IF;
            END LOOP;
            RETURN v_all_moves;
        END IF;
    END IF;

    RETURN v_simple_moves;
END find_all_player_moves;