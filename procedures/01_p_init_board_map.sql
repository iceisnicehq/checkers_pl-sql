PROCEDURE p_init_board_map(p_board_size IN NUMBER) IS
    v_idx       PLS_INTEGER;
    v_notation  VARCHAR2(10);
    v_field_rec rec_board_field;
BEGIN
    IF p_board_size = g_current_map_size THEN
        RETURN;
    END IF;
    
    g_map_by_notation.DELETE;
    g_map_by_idx.DELETE;
    
    FOR r IN 1 .. p_board_size LOOP
        FOR c IN 1 .. p_board_size LOOP
            v_idx := ((p_board_size - r) * p_board_size) + c;
            
            v_notation := CHR(ASCII('a') + c - 1) || r;

            v_field_rec.idx      := v_idx;
            v_field_rec.notation := v_notation;
            v_field_rec.row_num  := r;
            v_field_rec.col_num  := c;

            g_map_by_notation(v_notation) := v_field_rec;
            g_map_by_idx(v_idx)           := v_field_rec;
            
        END LOOP;
    END LOOP;
    
    g_current_map_size := p_board_size;
    
END p_init_board_map;
