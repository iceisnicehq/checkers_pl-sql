PROCEDURE make_move(p_move_notation IN VARCHAR2) IS
    v_game_id   NUMBER;
    v_game      games%ROWTYPE;
    v_player_id players.player_id%TYPE;
    v_human_msg VARCHAR2(2000);
    v_ai_msg    VARCHAR2(2000);
    v_error_msg VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    v_game_id   := get_active_game(v_player_id);
    
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id; 
    
    IF v_game_id IS NULL THEN
        v_error_msg := 'Нет активных игр, чтобы сделать ход.';
        p_audit_log(v_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status != 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') еще не активна. Противник не подключился.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (v_game.current_turn = 'W' AND v_game.player_white_id != v_player_id) OR 
       (v_game.current_turn = 'B' AND v_game.player_black_id != v_player_id) 
    THEN
        v_error_msg := 'Сейчас не ваш ход. (ID Игры: ' || v_game_id || ', Очередь: ' || v_game.current_turn || ').';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    p_process_move(v_game_id, TRIM(p_move_notation), v_player_id, v_human_msg);

    IF INSTR(LOWER(v_human_msg), 'неверный ход') > 0 OR INSTR(LOWER(v_human_msg), 'нелегальный ход') > 0 THEN
        RETURN;
    END IF;

    IF v_human_msg IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(v_human_msg);
    END IF;

    SELECT status INTO v_game.status FROM games WHERE game_id = v_game_id;

    print_active_board(p_game_id => v_game_id);

    DECLARE
        v_next_game_state games%ROWTYPE;
        v_ai_move         VARCHAR2(50);
        v_ai_board_pos    VARCHAR2(100);
    BEGIN
        SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;

        IF v_next_game_state.status = 'A' AND v_next_game_state.ai_difficulty IS NOT NULL AND
           ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id IS NULL) OR
            (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id IS NULL))
        THEN

            v_ai_board_pos := f_get_current_board_position(v_game_id, v_next_game_state.rule_id);

            IF INSTR(v_ai_board_pos, c_empty_field) > 0 THEN
                v_ai_board_pos := encode_board(v_ai_board_pos);
            END IF;

            DECLARE
                v_ai_difficulty CHAR(1) := v_next_game_state.ai_difficulty;
            BEGIN
                v_ai_move := get_ai_move(
                    p_board_position => v_ai_board_pos, 
                    p_ai_color       => v_next_game_state.current_turn, 
                    p_rule_id        => v_next_game_state.rule_id, 
                    p_difficulty     => v_ai_difficulty
                );
            END;

            IF v_ai_move IS NOT NULL THEN
                p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                
                print_active_board(p_game_id => v_game_id);
            END IF;
        END IF;
    END;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END make_move;