-- @function f_get_board_as_clob
-- @brief Returns a CLOB representing the board for display.
-- @dependencies:
--   - decode_board (function)
--   - p_init_board_map (procedure)
--   - c_empty_field (constant)
--   - t_map_indices (type)

FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2,
    p_highlight_indices IN t_map_indices DEFAULT t_map_indices()
) RETURN CLOB IS
    v_clob          CLOB;
    v_char          CHAR(1);
    v_linear_idx    PLS_INTEGER;
    v_decoded_board VARCHAR2(128) := decode_board(p_board_position); -- Было 200
    c_nl CONSTANT   VARCHAR2(1)   := CHR(10);
    
    v_board_size    PLS_INTEGER;
    v_total_squares PLS_INTEGER;
    v_header        VARCHAR2(128) := '  |'; -- Было 200
    v_separator     VARCHAR2(128) := '--+'; -- Было 200
    
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
        -- Для доски 10x10 нужна буква 'j' (a-i, затем j)
        DECLARE
            v_col_letter CHAR(1);
        BEGIN
            IF c <= 9 THEN
                v_col_letter := CHR(ASCII('A') + c - 1);
            ELSE
                -- Для 10-й колонки используем 'J' (или можно 'j', но обычно заглавные)
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
    
EXCEPTION
    WHEN OTHERS THEN
        IF DBMS_LOB.istemporary(v_clob) = 1 THEN
            DBMS_LOB.freetemporary(v_clob);
        END IF;
        DBMS_LOB.createtemporary(v_clob, TRUE);
        DBMS_LOB.append(v_clob, 'КРИТИЧЕСКАЯ ОШИБКА в f_get_board_as_clob: ' || SQLERRM);
        RETURN v_clob;
END f_get_board_as_clob;