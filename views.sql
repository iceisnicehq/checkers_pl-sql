        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);
        FOR r IN REVERSE 1..8 LOOP
            DBMS_LOB.append(v_clob, r || ' |');
            FOR c IN 1..8 LOOP
                IF MOD(r + c, 2) != 0 THEN
                    v_char := SUBSTR(v_board_position, ((8-r)*8)+c, 1);
                    IF v_char = c_empty_field THEN
                        DBMS_LOB.append(v_clob, '[ ]');
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
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);
        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);