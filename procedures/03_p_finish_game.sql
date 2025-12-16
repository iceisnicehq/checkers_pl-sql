PROCEDURE p_finish_game(
    p_game_id           IN NUMBER,
    p_status            IN CHAR,
    p_winner_color      IN CHAR DEFAULT NULL,
    p_puzzle_status     IN CHAR DEFAULT NULL,
    p_audit_event       IN VARCHAR2,
    p_player_id         IN NUMBER DEFAULT NULL
) IS
    v_game games%ROWTYPE;
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id;

    UPDATE games
    SET status              = p_status,
        end_time            = SYSDATE,
        winner_player_color = p_winner_color,
        puzzle_status       = NVL(p_puzzle_status, puzzle_status)
    WHERE game_id = p_game_id;

    UPDATE spectators 
    SET left_at = SYSDATE 
    WHERE game_id = p_game_id AND left_at IS NULL;

    p_audit_log(p_player_id, p_game_id, p_audit_event);

    IF v_game.match_id IS NULL THEN
        p_update_ratings(p_game_id);
    END IF;

    IF v_game.match_id IS NOT NULL THEN
        DECLARE
            v_match matches%ROWTYPE;
            v_first_game games%ROWTYPE;
            v_player1_id players.player_id%TYPE;
            v_player2_id players.player_id%TYPE;
            v_player1_wins NUMBER := 0;
            v_player2_wins NUMBER := 0;
            v_games_to_win NUMBER;
            v_next_game_id NUMBER;
            v_next_player_color CHAR(1);
            v_season_id seasons.season_id%TYPE;
            v_match_rule_id NUMBER;
        BEGIN
            SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;

            SELECT * INTO v_first_game 
            FROM (
                SELECT * 
                FROM games 
                WHERE match_id = v_game.match_id 
                ORDER BY game_id ASC
            )
            WHERE ROWNUM = 1;
            
            v_player1_id := v_first_game.player_white_id;
            v_player2_id := v_first_game.player_black_id;
            v_games_to_win := v_match.games_to_win;
            v_match_rule_id := v_first_game.rule_id;

            FOR r IN (
                SELECT winner_player_color, status
                FROM games
                WHERE match_id = v_game.match_id
                  AND game_id != p_game_id
                  AND status IN ('V', 'D', 'T', 'R')
            ) LOOP
                IF r.status IN ('V', 'R') THEN
                    IF r.winner_player_color = 'W' THEN
                        v_player1_wins := v_player1_wins + 1;
                    ELSIF r.winner_player_color = 'B' THEN
                        v_player2_wins := v_player2_wins + 1;
                    END IF;
                END IF;
            END LOOP;
            
            IF p_status IN ('V', 'R') AND p_winner_color IS NOT NULL THEN
                IF p_winner_color = 'W' THEN
                    v_player1_wins := v_player1_wins + 1;
                ELSIF p_winner_color = 'B' THEN
                    v_player2_wins := v_player2_wins + 1;
                END IF;
            END IF;

            IF v_match.status = 'C' THEN
                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                IF v_match.winner_player_id = v_player1_id THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player1_wins * 16) + (10 * v_games_to_win))
                    WHERE player_id = v_player1_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player2_wins * 16) - (10 * v_games_to_win))
                    WHERE player_id = v_player2_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                ELSE
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player1_wins * 16) - (10 * v_games_to_win))
                    WHERE player_id = v_player1_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player2_wins * 16) + (10 * v_games_to_win))
                    WHERE player_id = v_player2_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                END IF;
            ELSIF v_player1_wins >= TRUNC((v_games_to_win + 1) / 2) THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_player1_id
                WHERE match_id = v_game.match_id;
                p_audit_log(v_player1_id, p_game_id, 'MATCH_WON');

                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player1_wins * 16) + (10 * v_games_to_win))
                WHERE player_id = v_player1_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player2_wins * 16) - (10 * v_games_to_win))
                WHERE player_id = v_player2_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
            ELSIF v_player2_wins >= TRUNC((v_games_to_win + 1) / 2) THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_player2_id
                WHERE match_id = v_game.match_id;
                p_audit_log(v_player2_id, p_game_id, 'MATCH_WON');

                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player1_wins * 16) - (10 * v_games_to_win))
                WHERE player_id = v_player1_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player2_wins * 16) + (10 * v_games_to_win))
                WHERE player_id = v_player2_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
            ELSIF v_match.status != 'C' THEN

                DECLARE
                    v_game_count NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_game_count
                    FROM games
                    WHERE match_id = v_game.match_id;
                    
                    v_next_player_color := CASE WHEN MOD(v_game_count, 2) = 0 THEN 'B' ELSE 'W' END;
                    
                    INSERT INTO games (
                        match_id, rule_id, player_white_id, player_black_id,
                        creator_player_color, status, current_turn,
                        time_limit_move_sec, time_limit_game_sec,
                        draw_moves_limit, enable_pos_repetition_draw
                    )
                    VALUES (
                        v_game.match_id, v_first_game.rule_id,
                        CASE v_next_player_color WHEN 'W' THEN v_player1_id ELSE v_player2_id END,
                        CASE v_next_player_color WHEN 'W' THEN v_player2_id ELSE v_player1_id END,
                        v_next_player_color, 'A', 'W',
                        v_first_game.time_limit_move_sec,
                        v_first_game.time_limit_game_sec,
                        v_first_game.draw_moves_limit,
                        v_first_game.enable_pos_repetition_draw
                    )
                    RETURNING game_id INTO v_next_game_id;
                    
                    p_audit_log(v_player1_id, v_next_game_id, 'MATCH_NEXT_GAME_CREATED');
                END;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
    END IF;
    
    COMMIT;
END p_finish_game;