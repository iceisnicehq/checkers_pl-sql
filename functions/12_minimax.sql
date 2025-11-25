FUNCTION minimax(
    p_board         IN VARCHAR2,
    p_depth         IN PLS_INTEGER,
    p_alpha         IN NUMBER, 
    p_beta          IN NUMBER, 
    p_is_maximizing IN BOOLEAN,
    p_ai_color      IN CHAR,
    p_difficulty    IN NUMBER,
    p_rule_id       IN NUMBER
) RETURN r_minimax_result IS
    v_result         r_minimax_result;
    v_possible_moves t_move_list; 
    v_current_color  CHAR(1);
    v_local_alpha    NUMBER := p_alpha;
    v_local_beta     NUMBER := p_beta;
BEGIN
    v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;
    
    v_possible_moves := get_sorted_possible_moves(
        p_board   => p_board, 
        p_color   => v_current_color, 
        p_rule_id => p_rule_id
    );

    IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN
        v_result.score := evaluate_board(p_board, p_ai_color, p_difficulty);
        v_result.move := NULL;
        RETURN v_result;
    END IF;
    
    IF p_is_maximizing THEN
        v_result.score := -99999; 
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(128) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
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
                v_new_board   VARCHAR2(128) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
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
