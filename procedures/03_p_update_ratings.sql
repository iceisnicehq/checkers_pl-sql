PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
    v_game      games%ROWTYPE;
    v_season_id seasons.season_id%TYPE;

    -- Внутренняя процедура для атомарного обновления одного игрока
    PROCEDURE update_one_player(p_pid IN NUMBER, p_delta IN NUMBER) IS
        v_current_rating NUMBER;
    BEGIN
        IF p_pid IS NULL THEN RETURN; END IF; -- ИИ рейтинг не обновляем

        -- 1. Ищем текущий рейтинг или создаем запись, если её нет (Star 500)
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

        -- 2. Обновляем (не уходим ниже 0)
        UPDATE player_ratings
        SET rating = GREATEST(0, rating + p_delta)
        WHERE player_id = p_pid 
          AND rule_id = v_game.rule_id 
          AND season_id = v_season_id;
    END;

BEGIN
    -- Получаем данные игры
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN;

    -- Определяем сезон, в котором игра началась (используем start_time, а не SYSDATE)
    -- Это гарантирует, что рейтинг обновляется в сезоне начала игры, даже если игра закончилась в следующем сезоне
    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE v_game.start_time BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Если сезона для start_time нет, берем последний сезон, который начался до start_time
            SELECT MAX(season_id) INTO v_season_id 
            FROM seasons 
            WHERE start_date <= v_game.start_time;
    END;
    
    -- Если сезона нет вообще, выходим (сезоны должны создаваться через scheduler)
    IF v_season_id IS NULL THEN
        RETURN;
    END IF;

    -- Логика начисления
    IF v_game.status = 'V' THEN -- Victory (Кто-то выиграл)
        
        -- СЛУЧАЙ А: ПАЗЛ (Puzzle / Daily)
        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
                v_puzzle_created_by NUMBER;
            BEGIN
                -- Кто решал? (В пазлах играет создатель сессии)
                v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
                
                -- Проверяем, является ли пазл общим (не созданным пользователем)
                BEGIN
                    SELECT created_by_player_id INTO v_puzzle_created_by
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_puzzle_created_by := NULL;
                END;
                
                -- Рейтинг обновляется только для общих пазлов (created_by_player_id IS NULL)
                IF v_puzzle_created_by IS NULL THEN
                -- Проверяем, решал ли он эту задачу РАНЬШЕ (успешно)
                SELECT COUNT(*) INTO v_prev_solves
                FROM games
                WHERE puzzle_id = v_game.puzzle_id
                  AND (player_white_id = v_solver_id OR player_black_id = v_solver_id)
                  AND status = 'V'
                  AND game_id != p_game_id; -- Исключаем текущую сессию

                -- Если решил впервые -> +5 очков
                IF v_prev_solves = 0 THEN
                    update_one_player(v_solver_id, 5);
                    END IF;
                END IF;
            END;

        -- СЛУЧАЙ Б: ОБЫЧНАЯ ИГРА (PvP / PvE)
        ELSE
            -- Рейтинг обновляется только для PvP игр (не для PvE против AI)
            IF v_game.ai_difficulty IS NULL THEN
                -- Это PvP игра - обновляем рейтинг
            IF v_game.winner_player_color = 'W' THEN
                update_one_player(v_game.player_white_id, 16); -- Победитель
                update_one_player(v_game.player_black_id, -16); -- Проигравший
            ELSIF v_game.winner_player_color = 'B' THEN
                update_one_player(v_game.player_black_id, 16); -- Победитель
                update_one_player(v_game.player_white_id, -16); -- Проигравший
            END IF;
            END IF;
            -- Если ai_difficulty IS NOT NULL - это PvE против AI, рейтинг НЕ обновляется
        END IF;
        
    END IF;
    -- При ничьей (status = 'D') очки не меняются (согласно твоему описанию).
    
    -- Обработка матчей: создание следующей игры или завершение матча
    IF v_game.match_id IS NOT NULL THEN
        BEGIN
            DECLARE
                v_match matches%ROWTYPE;
                v_player1_id players.player_id%TYPE;
                v_player2_id players.player_id%TYPE;
                v_player1_wins NUMBER := 0;
                v_player2_wins NUMBER := 0;
                v_games_to_win NUMBER;
                v_next_game_id NUMBER;
                v_next_player_color CHAR(1);
            BEGIN
                SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;
                
                IF v_match.status = 'C' THEN
                    RETURN; -- Матч уже завершен
                END IF;
                
                DECLARE
                    v_first_game games%ROWTYPE;
                BEGIN
                    SELECT * INTO v_first_game 
                    FROM games 
                    WHERE match_id = v_game.match_id 
                    ORDER BY game_id ASC 
                    FETCH FIRST 1 ROW ONLY;
                    
                    v_player1_id := v_first_game.player_white_id;
                    v_player2_id := v_first_game.player_black_id;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        RETURN;
                END;
                
                FOR r IN (
                    SELECT winner_player_color, status
                    FROM games
                    WHERE match_id = v_game.match_id
                      AND status IN ('V', 'D', 'T', 'R')
                ) LOOP
                    IF r.status = 'V' THEN
                        IF r.winner_player_color = 'W' AND v_player1_id IS NOT NULL THEN
                            v_player1_wins := v_player1_wins + 1;
                        ELSIF r.winner_player_color = 'B' AND v_player2_id IS NOT NULL THEN
                            v_player2_wins := v_player2_wins + 1;
                        END IF;
                    END IF;
                END LOOP;
                
                v_games_to_win := v_match.games_to_win;
                
                IF v_player1_wins >= v_games_to_win THEN
                    UPDATE matches
                    SET status = 'C',
                        winner_player_id = v_player1_id
                    WHERE match_id = v_game.match_id;
                    p_audit_log(v_player1_id, p_game_id, 'MATCH_WON');
                    RETURN;
                ELSIF v_player2_wins >= v_games_to_win THEN
                    UPDATE matches
                    SET status = 'C',
                        winner_player_id = v_player2_id
                    WHERE match_id = v_game.match_id;
                    p_audit_log(v_player2_id, p_game_id, 'MATCH_WON');
                    RETURN;
                END IF;
                
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
                        v_next_player_color, 'C', 'W',
                        v_first_game.time_limit_move_sec,
                        v_first_game.time_limit_game_sec,
                        v_first_game.draw_moves_limit,
                        v_first_game.enable_pos_repetition_draw
                    )
                    RETURNING game_id INTO v_next_game_id;
                    
                    p_audit_log(v_player1_id, v_next_game_id, 'MATCH_NEXT_GAME_CREATED');
                END;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    NULL; -- Матч не найден, игнорируем
                WHEN OTHERS THEN
                    p_audit_log(NULL, p_game_id, 'MATCH_CONTINUATION_ERROR: ' || SQLERRM);
            END;
        END;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- Рейтинг не должен валить игру, просто логируем ошибку
        p_audit_log(NULL, p_game_id, 'RATING_ERROR: ' || SQLERRM);
END p_update_ratings;
