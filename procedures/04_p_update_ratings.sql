PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
    v_game      games%ROWTYPE;
    v_season_id seasons.season_id%TYPE;
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id;

    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE v_game.start_time BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            SELECT MAX(season_id) INTO v_season_id FROM seasons;
    END;

    IF v_game.status IN ('V', 'T', 'R') AND v_game.match_id IS NULL THEN

        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
                v_puzzle_created_by NUMBER;
                v_is_daily_puzzle BOOLEAN := (v_game.is_daily_puzzle = 'Y');
                v_puzzle_date DATE;
                v_today DATE := TRUNC(SYSDATE);
            BEGIN

                IF v_game.status = 'V' AND v_game.puzzle_status = 's' THEN

                    v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;

                    SELECT created_by_player_id INTO v_puzzle_created_by
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;

                    IF v_puzzle_created_by IS NULL AND v_solver_id IS NOT NULL THEN

                        IF v_is_daily_puzzle THEN
                            -- Для daily puzzle проверяем, решена ли уже сегодняшняя задача этим игроком
                            BEGIN
                                SELECT dp.puzzle_date INTO v_puzzle_date
                                FROM daily_puzzles dp
                                WHERE dp.puzzle_id = v_game.puzzle_id
                                  AND dp.puzzle_date = v_today
                                  AND ROWNUM = 1;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_puzzle_date := NULL;
                            END;

                            IF v_puzzle_date IS NOT NULL THEN
                                -- Проверяем, решена ли уже сегодняшняя daily puzzle этим игроком
                                SELECT COUNT(*) INTO v_prev_solves
                                FROM games g
                                JOIN daily_puzzles dp ON g.puzzle_id = dp.puzzle_id
                                WHERE dp.puzzle_date = v_today
                                  AND (g.player_white_id = v_solver_id OR g.player_black_id = v_solver_id)
                                  AND g.status = 'V'
                                  AND g.puzzle_status = 's'
                                  AND g.is_daily_puzzle = 'Y'
                                  AND g.game_id != p_game_id;
                            ELSE
                                v_prev_solves := 1; -- Если не найдена сегодняшняя daily puzzle, не начисляем
                            END IF;
                        ELSE
                            -- Для обычных задач проверяем по puzzle_id (как раньше)
                        SELECT COUNT(*) INTO v_prev_solves
                        FROM games
                        WHERE puzzle_id = v_game.puzzle_id
                          AND (player_white_id = v_solver_id OR player_black_id = v_solver_id)
                          AND status = 'V'
                          AND puzzle_status = 's'
                          AND game_id != p_game_id;
                        END IF;

                        IF v_prev_solves = 0 THEN

                            INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                            SELECT v_solver_id, v_game.rule_id, v_season_id, 5
                            FROM DUAL
                            WHERE NOT EXISTS (
                                SELECT 1 FROM player_ratings 
                                WHERE player_id = v_solver_id 
                                  AND rule_id = v_game.rule_id 
                                  AND season_id = v_season_id
                            );
                            
                            UPDATE player_ratings
                            SET rating = GREATEST(0, rating + 5)
                            WHERE player_id = v_solver_id 
                              AND rule_id = v_game.rule_id 
                              AND season_id = v_season_id;
                        END IF;
                    END IF;
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    NULL;
            END;

        ELSE

            IF v_game.ai_difficulty IS NULL THEN

                IF v_game.winner_player_color = 'W' THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + 16)
                    WHERE player_id = v_game.player_white_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating - 16)
                    WHERE player_id = v_game.player_black_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                ELSIF v_game.winner_player_color = 'B' THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + 16)
                    WHERE player_id = v_game.player_black_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating - 16)
                    WHERE player_id = v_game.player_white_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                END IF;
            END IF;

        END IF;
        
    END IF;

END p_update_ratings;