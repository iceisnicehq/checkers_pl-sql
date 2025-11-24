-- @procedure p_update_ratings
-- @brief Updates player ratings after a game is finished.
-- @dependencies:
--   - (none)

-- [РЕАЛИЗАЦИЯ] +5 Puzzle, +16 Win, -16 Loss, Min 0.

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
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN;
    END;

    -- Определяем текущий сезон (берем последний активный или просто максимальный ID)
    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE SYSDATE BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Если сезона нет, берем последний созданный (fallback)
            SELECT MAX(season_id) INTO v_season_id FROM seasons;
            IF v_season_id IS NULL THEN RETURN; END IF; -- Если вообще нет сезонов, выходим
    END;

    -- Логика начисления
    IF v_game.status = 'V' THEN -- Victory (Кто-то выиграл)
        
        -- СЛУЧАЙ А: ПАЗЛ (Puzzle / Daily)
        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
            BEGIN
                -- Кто решал? (В пазлах играет создатель сессии)
                v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
                
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
            END;

        -- СЛУЧАЙ Б: ОБЫЧНАЯ ИГРА (PvP / PvE)
        ELSE
            IF v_game.winner_player_color = 'W' THEN
                update_one_player(v_game.player_white_id, 16); -- Победитель
                update_one_player(v_game.player_black_id, -16); -- Проигравший
            ELSIF v_game.winner_player_color = 'B' THEN
                update_one_player(v_game.player_black_id, 16); -- Победитель
                update_one_player(v_game.player_white_id, -16); -- Проигравший
            END IF;
        END IF;
        
    END IF;
    -- При ничьей (status = 'D') очки не меняются (согласно твоему описанию).

EXCEPTION
    WHEN OTHERS THEN
        -- Рейтинг не должен валить игру, просто логируем ошибку
        p_audit_log(NULL, p_game_id, 'RATING_ERROR: ' || SQLERRM);
END p_update_ratings;