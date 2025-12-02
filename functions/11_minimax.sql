FUNCTION minimax(
    p_board         IN VARCHAR2,
    p_depth         IN PLS_INTEGER,
    p_alpha         IN NUMBER, 
    p_beta          IN NUMBER, 
    p_is_maximizing IN BOOLEAN,
    p_ai_color      IN CHAR,
    p_difficulty    IN CHAR,
    p_rule_id       IN NUMBER
) RETURN r_minimax_result IS
    v_result         r_minimax_result;
    v_possible_moves t_move_list; 
    v_current_color  CHAR(1);
    v_local_alpha    NUMBER := p_alpha;
    v_local_beta     NUMBER := p_beta;

    c_man_value      CONSTANT NUMBER := 10;
    c_king_value     CONSTANT NUMBER := 50;
    c_side_val       CONSTANT NUMBER := 20; 
    c_wall_val       CONSTANT NUMBER := 10;
BEGIN
    v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;

    v_possible_moves := find_all_player_moves(p_board, v_current_color, p_rule_id);

    IF v_possible_moves.COUNT >= 2 THEN
        DECLARE
            v_temp r_move;
            v_board_size PLS_INTEGER := SQRT(LENGTH(p_board));
            v_end_row PLS_INTEGER;
            v_start_piece CHAR(1);
            v_promotion_row PLS_INTEGER := CASE v_current_color WHEN 'W' THEN v_board_size ELSE 1 END;
        BEGIN

            p_init_board_map(v_board_size);

            FOR i IN 1..v_possible_moves.COUNT LOOP
                v_possible_moves(i).score := 0;

                IF v_possible_moves(i).is_capture = 'Y' THEN
                    v_possible_moves(i).score := 1000 + v_possible_moves(i).capture_count;
                ELSE

                    IF v_possible_moves(i).path.COUNT > 0 THEN
                        v_start_piece := SUBSTR(p_board, v_possible_moves(i).path(1).start_idx, 1);
                        v_end_row := g_map_by_idx(v_possible_moves(i).path(v_possible_moves(i).path.COUNT).end_idx).row_num;

                        IF (v_start_piece IN (c_white_man, c_black_man)) AND (v_end_row = v_promotion_row) THEN
                            v_possible_moves(i).score := 100;
                        END IF;
                    END IF;
                END IF;
            END LOOP;

            FOR i IN 1 .. v_possible_moves.COUNT - 1 LOOP
                FOR j IN i + 1 .. v_possible_moves.COUNT LOOP
                    IF v_possible_moves(i).score < v_possible_moves(j).score THEN
                        v_temp := v_possible_moves(i);
                        v_possible_moves(i) := v_possible_moves(j);
                        v_possible_moves(j) := v_temp;
                    END IF;
                END LOOP;
            END LOOP;
        END;
    END IF;

    IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN

        DECLARE
            v_score          NUMBER := 0;
            v_piece          CHAR(1);
            v_total_squares  PLS_INTEGER;
            v_board_size     PLS_INTEGER;
            v_ai_pieces_cnt  PLS_INTEGER := 0;
            v_opp_pieces_cnt PLS_INTEGER := 0;
        BEGIN
            v_total_squares := LENGTH(p_board);
            v_board_size    := SQRT(v_total_squares);
            p_init_board_map(v_board_size);

            FOR i IN 1..v_total_squares LOOP
                v_piece := SUBSTR(p_board, i, 1);
                
                IF v_piece != c_empty_field THEN
                    DECLARE
                        v_piece_value    NUMBER;
                        v_multiplier     NUMBER;
                        v_piece_color    CHAR(1);
                        v_field_rec      rec_board_field := g_map_by_idx(i);
                        v_row            PLS_INTEGER     := v_field_rec.row_num;
                        v_col            PLS_INTEGER     := v_field_rec.col_num;
                        v_position_bonus NUMBER := 0;
                    BEGIN
                        v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                        
                        IF v_piece_color = p_ai_color THEN
                            v_ai_pieces_cnt := v_ai_pieces_cnt + 1;
                        ELSE
                            v_opp_pieces_cnt := v_opp_pieces_cnt + 1;
                        END IF;

                        v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                        v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                        
                        v_score := v_score + (v_piece_value * v_multiplier);

                        IF p_difficulty != 'H' THEN
                            IF v_col = 1 OR v_col = v_board_size THEN
                                v_position_bonus := v_position_bonus + c_side_val;
                            END IF;

                            IF v_piece_color = 'W' THEN
                                v_position_bonus := v_position_bonus + ( (v_row / v_board_size) * c_wall_val );
                            ELSE
                                v_position_bonus := v_position_bonus + ( (( (v_board_size + 1) - v_row) / v_board_size) * c_wall_val );
                            END IF;
                        END IF;
                        
                        v_score := v_score + (v_position_bonus * v_multiplier);
                    END;
                END IF;
            END LOOP;
            
            IF v_ai_pieces_cnt > 0 AND v_opp_pieces_cnt = 0 THEN
                v_result.score := 9999;
            ELSIF v_ai_pieces_cnt = 0 AND v_opp_pieces_cnt > 0 THEN
                v_result.score := -9999;
            ELSE
                v_result.score := v_score;
            END IF;
        END;
        
        v_result.move := NULL;
        RETURN v_result;
    END IF;
    
    IF p_is_maximizing THEN
        v_result.score := -99999; 
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => FALSE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );
                
                IF v_eval_result.score > v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;
                
                v_local_alpha := GREATEST(v_local_alpha, v_eval_result.score);
                
                IF v_local_beta <= v_local_alpha THEN
                    EXIT;
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    ELSE
        v_result.score := 99999;
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => TRUE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );

                IF v_eval_result.score < v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;

                v_local_beta := LEAST(v_local_beta, v_eval_result.score);

                IF v_local_beta <= v_local_alpha THEN
                    EXIT;
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    END IF;
END minimax;