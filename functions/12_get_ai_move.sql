FUNCTION get_ai_move(
    p_board_position IN game_moves.board_position%TYPE,
    p_ai_color       IN games.current_turn%TYPE,
    p_rule_id        IN games.rule_id%TYPE,
    p_difficulty     IN games.ai_difficulty%TYPE
) RETURN VARCHAR2 IS
    v_best_move_str  VARCHAR2(100);
    v_chosen_move    r_move;
    v_decoded_board  VARCHAR2(100) := decode_board(p_board_position);
    v_search_depth   PLS_INTEGER := 2;
    v_minimax_result r_minimax_result;
    v_alpha          NUMBER;
    v_beta           NUMBER;
    v_board_size     PLS_INTEGER;
BEGIN
    v_board_size := SQRT(LENGTH(v_decoded_board));
    p_init_board_map(v_board_size);

    DECLARE
        v_all_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
        v_capture_count PLS_INTEGER := 0;
    BEGIN

        FOR i IN 1 .. v_all_moves.COUNT LOOP
            IF v_all_moves(i).is_capture = 'Y' THEN
                v_capture_count := v_capture_count + 1;
            END IF;
        END LOOP;

        IF v_capture_count = 1 AND v_all_moves.COUNT = 1 THEN
            v_best_move_str := f_move_to_notation(v_all_moves(1), v_board_size);
            RETURN v_best_move_str;
        END IF;
    END;

    IF p_difficulty = 'M' THEN
        v_search_depth := 4;
    ELSIF p_difficulty = 'H' THEN
        v_search_depth := 8;
    END IF;
    v_alpha := -99999;
    v_beta  := 99999;

    v_minimax_result := minimax(
        p_board         => v_decoded_board, 
        p_depth         => v_search_depth, 
        p_alpha         => v_alpha, 
        p_beta          => v_beta, 
        p_is_maximizing => TRUE, 
        p_ai_color      => p_ai_color, 
        p_difficulty    => p_difficulty,
        p_rule_id       => p_rule_id
    );
    v_chosen_move := v_minimax_result.move;

    IF p_difficulty = 'E' AND DBMS_RANDOM.VALUE < 0.25 THEN
         DECLARE
            v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
            IF v_random_moves.COUNT > 0 THEN
                 v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
            END IF;
         END;
     END IF;

    IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
         v_best_move_str := f_move_to_notation(v_chosen_move, v_board_size);
    ELSE

         v_best_move_str := NULL;
    END IF;

    RETURN v_best_move_str;
END get_ai_move;