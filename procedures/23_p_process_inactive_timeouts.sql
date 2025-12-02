PROCEDURE p_process_inactive_timeouts(
    p_timeout_hours IN NUMBER DEFAULT 24
) IS
    v_updated_count PLS_INTEGER := 0;
    v_decoded_board VARCHAR2(100);
    v_score NUMBER;
    v_winner_color CHAR(1);
    c_man_value      CONSTANT NUMBER := 1;
    c_king_value     CONSTANT NUMBER := 4;
    c_empty_field    CONSTANT CHAR(1) := '+';
BEGIN

    FOR r IN (
        SELECT g.game_id, g.rule_id, g.current_turn
        FROM games g
        WHERE g.status = 'A'
          AND (

              (EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
               AND (SELECT MAX(move_timestamp) FROM game_moves WHERE game_id = g.game_id) < SYSDATE - (p_timeout_hours / 24))
              OR

              (NOT EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
               AND g.start_time < SYSDATE - (p_timeout_hours / 24))
          )
    ) LOOP
        BEGIN

            BEGIN
                SELECT decode_board(board_position) INTO v_decoded_board
                FROM game_moves
                WHERE game_id = r.game_id
                ORDER BY move_number DESC
                FETCH FIRST 1 ROW ONLY;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN

                    v_decoded_board := get_initial_position(r.rule_id);
            END;

            DECLARE
                v_piece          CHAR(1);
                v_total_squares  NUMBER;
                v_board_size     NUMBER;
            BEGIN
                v_total_squares := LENGTH(v_decoded_board);
                v_board_size    := SQRT(v_total_squares);
                p_init_board_map(v_board_size);
                
                v_score := 0;
                FOR i IN 1..v_total_squares LOOP
                    v_piece := SUBSTR(v_decoded_board, i, 1);
                    
                    IF v_piece != c_empty_field THEN
                        DECLARE
                            v_piece_value    NUMBER;
                            v_multiplier     NUMBER;
                        BEGIN

                            IF v_piece IN ('w', 'W') THEN
                                v_multiplier := 1;
                            ELSE
                                v_multiplier := -1;
                            END IF;

                            v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                            
                            v_score := v_score + (v_piece_value * v_multiplier);
                        END;
                    END IF;
                END LOOP;
            END;

            IF v_score > 0 THEN
                v_winner_color := 'W';
            ELSIF v_score < 0 THEN
                v_winner_color := 'B';
            ELSE

                v_winner_color := CASE WHEN r.current_turn = 'W' THEN 'B' ELSE 'W' END;
            END IF;

            p_finish_game(
                p_game_id      => r.game_id,
                p_status       => 'T',
                p_winner_color => v_winner_color,
                p_audit_event  => 'INACTIVE_GAME_TIMEOUT: Score=' || v_score || ', Winner=' || v_winner_color,
                p_player_id    => NULL
            );
            
            v_updated_count := v_updated_count + 1;
        EXCEPTION
            WHEN OTHERS THEN

                NULL;
        END;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN

        NULL;
END p_process_inactive_timeouts;