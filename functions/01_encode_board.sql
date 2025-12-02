FUNCTION encode_board(p_decoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_encoded_board VARCHAR2(100) := '';
    v_plus_count    PLS_INTEGER := 0;
    v_char          CHAR(1);
BEGIN
    FOR i IN 1 .. LENGTH(p_decoded_board) LOOP
        v_char := SUBSTR(p_decoded_board, i, 1);
        IF v_char = c_empty_field THEN
            v_plus_count := v_plus_count + 1;
        ELSE
            IF v_plus_count > 0 THEN
                v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
                v_plus_count := 0;
            END IF;
            v_encoded_board := v_encoded_board || v_char;
        END IF;
    END LOOP;

    IF v_plus_count > 0 THEN
        v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
    END IF;

    RETURN v_encoded_board;
END encode_board;