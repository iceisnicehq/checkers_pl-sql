PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
    v_game      games%ROWTYPE;
    v_season_id seasons.season_id%TYPE;

    PROCEDURE update_one_player(p_pid IN NUMBER, p_delta IN NUMBER) IS
        v_current_rating NUMBER;
    BEGIN
        IF p_pid IS NULL THEN RETURN; END IF;

        BEGIN
            SELECT rating INTO v_current_rating
            FROM player_ratings
            WHERE player_id = p_pid 
              AND rule_id = v_game.rule_id 
              AND season_id = v_season_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_current_rating := 500;
                INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                VALUES (p_pid, v_game.rule_id, v_season_id, v_current_rating);
        END;

        UPDATE player_ratings
        SET rating = GREATEST(0, rating + p_delta)
        WHERE player_id = p_pid 
          AND rule_id = v_game.rule_id 
          AND season_id = v_season_id;
    END;

BEGIN
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN;
    END;

    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE SYSDATE BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            BEGIN
                SELECT MAX(season_id) INTO v_season_id FROM seasons;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_season_id := NULL;
            END;
            
            IF v_season_id IS NULL THEN
                DECLARE
                    v_current_month DATE := TRUNC(SYSDATE, 'MM');
                    v_next_month DATE := ADD_MONTHS(v_current_month, 1);
                    v_season_name VARCHAR2(100);
                    v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
                    );
                    v_month_num PLS_INTEGER;
                    v_year_num PLS_INTEGER;
                BEGIN
                    v_month_num := EXTRACT(MONTH FROM v_current_month);
                    v_year_num := EXTRACT(YEAR FROM v_current_month);
                    v_season_name := v_month_names(v_month_num) || '-' || v_year_num;
                    
                    INSERT INTO seasons (season_name, start_date, end_date)
                    VALUES (v_season_name, v_current_month, v_next_month - INTERVAL '1' SECOND)
                    RETURNING season_id INTO v_season_id;
                    
                    COMMIT;
                EXCEPTION
                    WHEN OTHERS THEN
                        RETURN;
                END;
            END IF;
    END;

    IF v_game.ai_difficulty IS NOT NULL AND v_game.puzzle_id IS NULL THEN
        p_audit_log(NULL, p_game_id, 'RATING_SKIP_AI_GAME');
        RETURN;
    END IF;

    IF v_game.status = 'V' THEN
        
        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
                v_puzzle_created_by NUMBER;
            BEGIN
                v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
                
                BEGIN
                    SELECT created_by_player_id INTO v_puzzle_created_by
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_puzzle_created_by := NULL;
                END;
                
                IF v_puzzle_created_by IS NULL THEN
                    SELECT COUNT(*) INTO v_prev_solves
                    FROM games
                    WHERE puzzle_id = v_game.puzzle_id
                      AND (player_white_id = v_solver_id OR player_black_id = v_solver_id)
                      AND status = 'V'
                      AND game_id != p_game_id;

                    IF v_prev_solves = 0 THEN
                        update_one_player(v_solver_id, 5);
                    ELSE
                        p_audit_log(NULL, p_game_id, 'RATING_SKIP_PUZZLE_REPEAT');
                    END IF;
                ELSE
                    p_audit_log(NULL, p_game_id, 'RATING_SKIP_USER_PUZZLE');
                END IF;
            END;

        ELSE
            IF v_game.ai_difficulty IS NULL THEN
                IF v_game.winner_player_color = 'W' THEN
                    update_one_player(v_game.player_white_id, 16);
                    update_one_player(v_game.player_black_id, -16);
                ELSIF v_game.winner_player_color = 'B' THEN
                    update_one_player(v_game.player_black_id, 16);
                    update_one_player(v_game.player_white_id, -16);
                END IF;
            END IF;
        END IF;
        
    END IF;
    
    IF v_game.match_id IS NOT NULL THEN
        p_process_match_continuation(v_game.match_id, p_game_id);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        p_audit_log(NULL, p_game_id, 'RATING_ERROR: ' || SQLERRM);
END p_update_ratings;
