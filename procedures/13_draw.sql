-- @procedure draw
-- @brief Manages draw offers (offer, accept, decline).
-- @dependencies:
--   - games (table)
--   - players (table)
--   - spectators (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - p_update_ratings (procedure)
--   - p_drop_move_timeout_job (procedure)

PROCEDURE draw(p_action IN CHAR) IS
    v_player_id players.player_id%TYPE;
    v_game_id   games.game_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(255);
    v_my_color  CHAR(1);
    v_action    CHAR(1) := UPPER(p_action);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    -- Проверка на зрителя
    DECLARE
        v_spectating_game_id NUMBER;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_spectating_game_id := NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя управлять ничьей.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    v_game_id := get_active_game(v_player_id);
    IF v_game_id IS NULL THEN
        v_error_msg := 'У вас нет активной игры.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN 
            v_error_msg := 'Активная игра ' || v_game_id || ' не найдена (возможно, баг).';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    IF v_game.status != 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') неактивна (статус: ' || v_game.status || ').';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.ai_difficulty IS NOT NULL THEN
        v_error_msg := 'Предложение ничьей недоступно в играх против ИИ.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.player_white_id = v_player_id THEN
        v_my_color := 'W';
    ELSE
        v_my_color := 'B';
    END IF;

    -- OFFER
    IF v_action = 'O' THEN
        IF v_game.draw_offer_status = 'O' THEN
            IF v_game.draw_offered_by_color = v_my_color THEN
                v_error_msg := 'Вы уже предложили ничью.';
            ELSE
                v_error_msg := 'Ваш оппонент уже предложил ничью. Вы можете ее принять (A) или отклонить (C).';
            END IF;
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET draw_offer_status     = 'O',
            draw_offered_by_color = v_my_color,
            draw_offered_at       = SYSDATE
        WHERE game_id = v_game_id;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_OFFER');
        DBMS_OUTPUT.PUT_LINE('Вы предложили ничью. Ожидайте ответа оппонента.');

    -- ACCEPT
    ELSIF v_action = 'A' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его принять.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        IF v_game.draw_offered_by_color = v_my_color THEN
            v_error_msg := 'Нельзя принять собственное предложение о ничьей.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        p_drop_move_timeout_job(v_game_id);
        
        UPDATE games
        SET status = 'D',
            end_time = SYSDATE,
            draw_offer_status = 'S'
        WHERE game_id = v_game_id;
        
        UPDATE spectators SET left_at = SYSDATE 
        WHERE game_id = v_game_id AND left_at IS NULL;

        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_ACCEPT');
        p_update_ratings(v_game_id); 
        DBMS_OUTPUT.PUT_LINE('Ничья по соглашению сторон.');

    -- CANCEL / DECLINE
    ELSIF v_action = 'C' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его отменить/отклонить.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET draw_offer_status     = NULL, 
            draw_offered_by_color = NULL,
            draw_offered_at       = NULL
        WHERE game_id = v_game_id;

        IF v_game.draw_offered_by_color = v_my_color THEN
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_CANCEL');
            DBMS_OUTPUT.PUT_LINE('Вы отменили свое предложение о ничьей.');
        ELSE
            p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_DECLINE');
            DBMS_OUTPUT.PUT_LINE('Вы отклонили предложение оппонента о ничьей.');
        END IF;

    ELSE
        v_error_msg := 'Неверный p_action: "' || p_action || '". Допустимые значения: O, A, C.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END draw;