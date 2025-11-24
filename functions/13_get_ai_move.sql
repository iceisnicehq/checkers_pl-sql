-- @function get_ai_move
-- @brief Main entry point for the AI to get its best move.
-- @dependencies:
--   - decode_board (function)
--   - p_init_board_map (procedure)
--   - minimax (function)
--   - find_all_player_moves (function)
--   - idx_to_notation (function)
--   - r_move, r_minimax_result, t_move_list (types)

FUNCTION get_ai_move(
    p_board_position IN game_moves.board_position%TYPE, -- ИСПРАВЛЕНО: game_moves вместо games
    p_ai_color       IN games.current_turn%TYPE,
    p_rule_id        IN games.rule_id%TYPE,
    p_difficulty     IN games.ai_difficulty%TYPE
) RETURN VARCHAR2 IS
    v_best_move_str  VARCHAR2(100);
    v_chosen_move    r_move;
    v_decoded_board  VARCHAR2(128) := decode_board(p_board_position);
    v_search_depth   PLS_INTEGER;
    v_minimax_result r_minimax_result;
    v_alpha          NUMBER;
    v_beta           NUMBER;
    v_board_size     PLS_INTEGER;
BEGIN
    v_board_size := SQRT(LENGTH(v_decoded_board));
    p_init_board_map(v_board_size);
    
    v_search_depth := CASE p_difficulty
                        WHEN 'E' THEN 4
                        WHEN 'M' THEN 8
                        WHEN 'H' THEN 12
                        ELSE 2
                      END;
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

    -- Fallback для Easy
    IF p_difficulty = 0 AND DBMS_RANDOM.VALUE < 0.25 THEN
         DECLARE
            v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
            IF v_random_moves.COUNT > 0 THEN
                 v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
            END IF;
         END;
     END IF;

    -- Формирование строки хода
    IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
         v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx, v_board_size);
         FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
             v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                              || idx_to_notation(v_chosen_move.path(j).end_idx, v_board_size);
         END LOOP;
    ELSE
        -- Fallback, если Minimax вернул NULL
         DECLARE
            v_fallback_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
             IF v_fallback_moves.COUNT > 0 THEN
                  v_chosen_move := v_fallback_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_fallback_moves.COUNT + 1)));
                  v_best_move_str := idx_to_notation(v_chosen_move.path(1).start_idx, v_board_size);
                  FOR j IN 1 .. v_chosen_move.path.COUNT LOOP
                      v_best_move_str := v_best_move_str || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                                       || idx_to_notation(v_chosen_move.path(j).end_idx, v_board_size);
                  END LOOP;
             ELSE
                  v_best_move_str := NULL;
             END IF;
         END;
    END IF;

    RETURN v_best_move_str;
END get_ai_move;