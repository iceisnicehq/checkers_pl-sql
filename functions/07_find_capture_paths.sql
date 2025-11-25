FUNCTION find_capture_paths(
    p_start_idx    IN PLS_INTEGER,
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_is_king      IN CHAR,
    p_rule_id      IN NUMBER,
    p_visited_path IN t_move_path DEFAULT t_move_path()
) RETURN t_move_list IS
    v_results             t_move_list := t_move_list();
    v_leaf_paths          t_move_list := t_move_list();
    v_opponent_man        CHAR(1);
    v_opponent_king       CHAR(1);
    v_decoded_board       VARCHAR2(128) := decode_board(p_board);
    
    v_rule                game_rules%ROWTYPE;
    v_board_size          PLS_INTEGER;
    v_total_squares       PLS_INTEGER;
    v_promotion_row       PLS_INTEGER;
    v_max_king_range      PLS_INTEGER;
    v_jump_directions     SYS.ODCINUMBERLIST;
    v_start_field         rec_board_field;
    
BEGIN
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_promotion_row   := v_board_size;
        v_max_king_range  := v_board_size - 1; 
        
        p_init_board_map(v_board_size);
        
        v_start_field := g_map_by_idx(p_start_idx);

        IF v_board_size = 8 THEN
            v_jump_directions := SYS.ODCINUMBERLIST(-18, -14, 14, 18);
        ELSE
            v_jump_directions := SYS.ODCINUMBERLIST(-22, -18, 18, 22);
        END IF;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_audit_log(NULL, NULL, 'find_capture_paths: Rule ' || p_rule_id || ' not found.');
            RETURN v_results;
        WHEN OTHERS THEN
            p_audit_log(NULL, NULL, 'find_capture_paths error: ' || SQLERRM);
            RETURN v_results; 
    END;
    
    IF p_player_color = 'W' THEN
        v_opponent_man  := c_black_man;
        v_opponent_king := c_black_king;
    ELSE
        v_opponent_man  := c_white_man;
        v_opponent_king := c_white_king;
    END IF;

    FOR i IN 1 .. v_jump_directions.COUNT LOOP
        DECLARE
            v_jump        PLS_INTEGER := v_jump_directions(i);
            v_land_idx    PLS_INTEGER;
            v_capture_idx PLS_INTEGER;
            v_is_visited  BOOLEAN := FALSE;
        BEGIN
            IF p_is_king = 'N' THEN
                v_land_idx    := p_start_idx + v_jump;
                v_capture_idx := p_start_idx + (v_jump / 2);

                IF v_land_idx BETWEEN 1 AND v_total_squares 
                   AND g_map_by_idx.EXISTS(v_land_idx)
                   AND ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) = 2 
                THEN
                    IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field 
                       AND SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) 
                    THEN
                        FOR k IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(k).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;

                        IF NOT v_is_visited THEN
                            DECLARE
                                v_becomes_king        CHAR(1) := 'N';
                                v_land_row            PLS_INTEGER := g_map_by_idx(v_land_idx).row_num; 
                                v_is_promotion_square BOOLEAN := (p_player_color = 'W' AND v_land_row = v_promotion_row) 
                                                              OR (p_player_color = 'B' AND v_land_row = 1);
                                v_step                r_move_step;
                                v_new_path            t_move_path := p_visited_path;
                                v_sub_paths           t_move_list;
                                v_move                r_move;
                            BEGIN
                                v_step.start_idx    := p_start_idx;
                                v_step.end_idx      := v_land_idx;
                                v_step.captured_idx := v_capture_idx;
                                v_new_path.EXTEND;
                                v_new_path(v_new_path.LAST) := v_step;

                                IF p_rule_id = 1 AND v_is_promotion_square THEN
                                    v_becomes_king := 'Y';
                                END IF;

                                v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, v_becomes_king, p_rule_id, v_new_path);

                                IF v_sub_paths.COUNT = 0 THEN
                                    v_move.path          := v_new_path;
                                    v_move.is_capture    := 'Y';
                                    v_move.capture_count := v_new_path.COUNT;
                                    v_leaf_paths.EXTEND;
                                    v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                ELSE
                                    FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                        v_results.EXTEND;
                                        v_results(v_results.LAST) := v_sub_paths(j);
                                    END LOOP;
                                END IF;
                            END;
                        END IF;
                    END IF;
                END IF;
                
            ELSE 
                FOR k IN 1 .. v_max_king_range LOOP 
                    v_capture_idx := p_start_idx + (v_jump / 2 * k);

                    IF v_capture_idx NOT BETWEEN 1 AND v_total_squares 
                       OR NOT g_map_by_idx.EXISTS(v_capture_idx)
                       OR ABS(v_start_field.col_num - g_map_by_idx(v_capture_idx).col_num) != k 
                    THEN
                        EXIT;
                    END IF;

                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN
                        FOR m IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(m).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;
                        IF v_is_visited THEN EXIT; END IF;

                        FOR l IN (k + 1) .. v_board_size LOOP 
                            v_land_idx := p_start_idx + (v_jump / 2 * l);
                            
                            IF v_land_idx NOT BETWEEN 1 AND v_total_squares 
                               OR NOT g_map_by_idx.EXISTS(v_land_idx)
                               OR ABS(v_start_field.col_num - g_map_by_idx(v_land_idx).col_num) != l 
                            THEN
                                EXIT;
                            END IF;
                            
                            IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field THEN
                                DECLARE
                                    v_step      r_move_step;
                                    v_new_path  t_move_path := p_visited_path;
                                    v_sub_paths t_move_list;
                                    v_move      r_move;
                                BEGIN
                                    v_step.start_idx    := p_start_idx;
                                    v_step.end_idx      := v_land_idx;
                                    v_step.captured_idx := v_capture_idx;
                                    v_new_path.EXTEND;
                                    v_new_path(v_new_path.LAST) := v_step;
                                    
                                    v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, 'Y', p_rule_id, v_new_path);

                                    IF v_sub_paths.COUNT = 0 THEN
                                        v_move.path          := v_new_path;
                                        v_move.is_capture    := 'Y';
                                        v_move.capture_count := v_new_path.COUNT;
                                        v_leaf_paths.EXTEND;
                                        v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                    ELSE
                                        FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                            v_results.EXTEND;
                                            v_results(v_results.LAST) := v_sub_paths(j);
                                        END LOOP;
                                    END IF;
                                END;
                            ELSE
                                EXIT;
                            END IF;
                        END LOOP;
                        EXIT;
                    END IF;
                    
                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) != c_empty_field THEN
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END;
    END LOOP;
    
    IF v_results.COUNT > 0 THEN
        RETURN v_results;
    ELSE
        RETURN v_leaf_paths;
    END IF;

END find_capture_paths;
