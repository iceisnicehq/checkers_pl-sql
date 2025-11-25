FUNCTION get_sorted_possible_moves(
    p_board   IN VARCHAR2,
    p_color   IN CHAR,
    p_rule_id IN NUMBER
) RETURN t_move_list IS
    v_moves t_move_list;
    v_temp  r_move;
BEGIN
    v_moves := find_all_player_moves(p_board, p_color, p_rule_id);
    
    IF v_moves.COUNT < 2 THEN
        RETURN v_moves;
    END IF;

    FOR i IN 1..v_moves.COUNT LOOP
        v_moves(i).score := 0;
        IF v_moves(i).is_capture = 'Y' THEN
            v_moves(i).score := 1000 + v_moves(i).capture_count;
        END IF;
    END LOOP;
    
    FOR i IN 1 .. v_moves.COUNT - 1 LOOP
        FOR j IN i + 1 .. v_moves.COUNT LOOP
            IF v_moves(i).score < v_moves(j).score THEN
                v_temp := v_moves(i);
                v_moves(i) := v_moves(j);
                v_moves(j) := v_temp;
            END IF;
        END LOOP;
    END LOOP;

    RETURN v_moves;

END get_sorted_possible_moves;
