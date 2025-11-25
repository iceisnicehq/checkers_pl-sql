-- @procedure join_game
-- @brief Allows a player to join an open or challenged game.
-- @dependencies:
--   - games (table)
--   - players (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

PROCEDURE join_game(p_game_id IN NUMBER) IS
    v_game             games%ROWTYPE;
    v_player_id        players.player_id%TYPE;
    v_active_game_id   NUMBER;
    v_error_msg        VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    -- Логика для ПРЯМОГО ВЫЗОВА (Challenged)
    IF v_game.status = 'C' THEN
        DECLARE
            v_creator_id players.player_id%TYPE;
        BEGIN
            IF v_game.creator_player_color = 'W' THEN
                v_creator_id := v_game.player_white_id;
            ELSE
                v_creator_id := v_game.player_black_id;
            END IF;
            
            -- Проверка: Игрок должен быть в слоте оппонента и не быть создателем
            IF NOT (v_player_id IN (v_game.player_white_id, v_game.player_black_id) AND v_player_id != v_creator_id) THEN
                v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK; 
                RETURN;
            END IF;
            
            -- Для вызова разрешаем присоединение даже если get_active_game находит эту игру
            -- (потому что игрок уже в игре, но статус 'C' - он должен "принять" вызов)
        END;
        
    -- Логика для ОТКРЫТОЙ ИГРЫ (Open)
    ELSIF v_game.status = 'O' THEN
        -- Нельзя присоединиться к своей же игре
        IF v_player_id = v_game.player_white_id OR v_player_id = v_game.player_black_id THEN
            v_error_msg := 'Нельзя присоединиться к собственной открытой игре (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        -- Для открытой игры проверяем, не занят ли игрок в другой игре
        v_active_game_id := get_active_game(v_player_id);
        IF v_active_game_id IS NOT NULL AND v_active_game_id != p_game_id THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
    ELSE
        v_error_msg := 'Нельзя присоединиться к этой игре (ID: ' || p_game_id || ', статус: '|| v_game.status || ').';
        p_audit_log(v_player_id, p_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;
    
    -- Обновление статуса игры
    IF v_game.status = 'O' THEN
        UPDATE games
        SET player_white_id = NVL(v_game.player_white_id, v_player_id),
            player_black_id = NVL(v_game.player_black_id, v_player_id),
            status          = 'A',
            start_time      = SYSDATE
        WHERE game_id = p_game_id;
    ELSE -- 'C'
        UPDATE games
        SET status     = 'A',
            start_time = SYSDATE
        WHERE game_id = p_game_id;
    END IF;
    
    -- Создаем джоб таймаута хода если есть лимит времени
    BEGIN
        p_create_move_timeout_job(p_game_id);
    EXCEPTION
        WHEN OTHERS THEN NULL; -- Игнорируем ошибки создания джоба
    END;
    
    p_audit_log(v_player_id, p_game_id, 'JOIN_GAME');
    DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при присоединении к игре: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 255));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END join_game;