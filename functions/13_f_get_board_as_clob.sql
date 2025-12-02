FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2
) RETURN CLOB IS
    v_empty_indices t_map_indices;
BEGIN

    RETURN f_get_board_as_clob(p_board_position, v_empty_indices);
END f_get_board_as_clob;

FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2,
    p_highlight_indices IN t_map_indices
) RETURN CLOB IS
    v_clob          CLOB;
    v_char          CHAR(1);
    v_linear_idx    PLS_INTEGER;
    v_decoded_board VARCHAR2(100) := decode_board(p_board_position);
    
    v_board_size    PLS_INTEGER;
    v_total_squares PLS_INTEGER;
    v_header        VARCHAR2(128) := '  |';
    v_separator     VARCHAR2(128) := '--+';
    
BEGIN
    DBMS_LOB.createtemporary(v_clob, TRUE);

    v_total_squares := LENGTH(v_decoded_board);
    v_board_size    := SQRT(v_total_squares);
    
    IF v_board_size != TRUNC(v_board_size) THEN 
        DBMS_LOB.append(v_clob, 'ОШИБКА: Длина доски (' || v_total_squares || ') не является полным квадратом.');
        RETURN v_clob;
    END IF;
    
    p_init_board_map(v_board_size);
    
    FOR c IN 1 .. v_board_size LOOP

        DECLARE
            v_col_letter CHAR(1);
        BEGIN
            IF c <= 9 THEN
                v_col_letter := CHR(ASCII('A') + c - 1);
            ELSE

                v_col_letter := 'J';
            END IF;
            v_header    := v_header    || ' ' || v_col_letter || ' ';
            v_separator := v_separator || '---';
        END;
    END LOOP;
    v_header    := v_header    || ' |';
    v_separator := v_separator || '+--';

    DBMS_LOB.append(v_clob, v_header || c_nl);
    DBMS_LOB.append(v_clob, v_separator || c_nl);

    FOR r IN REVERSE 1 .. v_board_size LOOP
        DBMS_LOB.append(v_clob, LPAD(r, 2, ' ') || '|');
        FOR c IN 1 .. v_board_size LOOP
            v_linear_idx := ((v_board_size - r) * v_board_size) + c;
            
            IF MOD(r + c, 2) = 0 THEN
                v_char := SUBSTR(v_decoded_board, v_linear_idx, 1);
                IF v_char = c_empty_field OR v_char IS NULL THEN
                     IF p_highlight_indices.EXISTS(v_linear_idx) THEN
                         DBMS_LOB.append(v_clob, '[.]');
                     ELSE
                         DBMS_LOB.append(v_clob, '[ ]');
                     END IF;
                ELSE
                    DBMS_LOB.append(v_clob, '[' || v_char || ']');
                END IF;
            ELSE
                DBMS_LOB.append(v_clob, '   ');
            END IF;
        END LOOP;
        DBMS_LOB.append(v_clob, '| ' || r);
        DBMS_LOB.append(v_clob, c_nl);
    END LOOP;
    
    DBMS_LOB.append(v_clob, v_separator || c_nl);
    DBMS_LOB.append(v_clob, v_header || c_nl);
    RETURN v_clob;
END f_get_board_as_clob;