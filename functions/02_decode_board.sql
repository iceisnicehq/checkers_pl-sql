FUNCTION decode_board(p_encoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_decoded_board VARCHAR2(100) := ''; 
    v_num_str       VARCHAR2(2) := '';
    v_char          CHAR(1);
    i               PLS_INTEGER := 1;
BEGIN
    WHILE i <= LENGTH(p_encoded_board) LOOP
        v_char := SUBSTR(p_encoded_board, i, 1);

        IF v_char BETWEEN '0' AND '9' THEN
            v_num_str := v_num_str || v_char;
        ELSE
            IF v_num_str IS NOT NULL THEN
                v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
                v_num_str := '';
            END IF;
            v_decoded_board := v_decoded_board || v_char;
        END IF;
        i := i + 1;
    END LOOP;

    IF v_num_str IS NOT NULL THEN
        v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
    END IF;

    RETURN v_decoded_board;
END decode_board;