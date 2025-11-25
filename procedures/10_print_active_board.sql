PROCEDURE print_active_board(
    p_game_id       IN NUMBER   DEFAULT NULL,
    p_username      IN VARCHAR2 DEFAULT NULL,
    p_wait_for_turn IN CHAR     DEFAULT 'N'
) IS
    v_target_game_id   games.game_id%TYPE;
    v_target_user_id   players.player_id%TYPE;
    v_target_username  players.username%TYPE;
    v_game             games%ROWTYPE;
    v_printable_board  CLOB;
    v_status_header    VARCHAR2(200);
    v_player_username  players.username%TYPE;
    v_move_count       NUMBER;
    c_nl CONSTANT      VARCHAR2(1) := CHR(10);
    v_error_msg        VARCHAR2(255);
    v_viewer_player_id players.player_id%TYPE;
    
    v_my_color         CHAR(1);
    v_loop_start_time  DATE;
    v_timeout_sec      NUMBER;
    v_wait_message     VARCHAR2(200);
    v_board_size       PLS_INTEGER;

BEGIN
    v_viewer_player_id := get_or_create_player_id(USER);
    
    IF p_game_id IS NOT NULL AND p_username IS NOT NULL THEN
        v_error_msg := 'Для поиска передайте процедуре только один параметр (имя пользователя или id игры).';
        p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    ELSIF p_game_id IS NOT NULL THEN
        v_target_game_id := p_game_id;
    ELSIF p_username IS NOT NULL THEN
        v_target_username := UPPER(p_username);
        BEGIN
            SELECT player_id INTO v_target_user_id FROM players WHERE username = v_target_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Пользователя "' || p_username || '" не существует.';
                p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        v_target_game_id := get_active_game(v_target_user_id);
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У пользователя "' || p_username || '" не найдено активных сессий.';
            p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    ELSE
        v_target_user_id := v_viewer_player_id; 
        v_target_game_id := get_active_game(v_target_user_id); 
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У вас нет активных игр.';
            p_audit_log(v_target_user_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    END IF;
    
    UPDATE spectators
    SET left_at = SYSDATE
    WHERE player_id = v_viewer_player_id
      AND left_at IS NULL
      AND game_id != v_target_game_id;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;
    
    IF v_viewer_player_id NOT IN (v_game.player_white_id, v_game.player_black_id)
       AND v_game.status IN ('A', 'O', 'C')
    THEN
        MERGE INTO spectators s
        USING (SELECT v_viewer_player_id AS player_id, v_target_game_id AS game_id FROM DUAL) d
        ON (s.player_id = d.player_id AND s.game_id = d.game_id AND s.left_at IS NULL)
        WHEN NOT MATCHED THEN
            INSERT (player_id, game_id, joined_at)
            VALUES (d.player_id, d.game_id, SYSDATE);
        
        p_audit_log(v_viewer_player_id, v_target_game_id, 'SPECTATOR_JOIN');
        DBMS_OUTPUT.PUT_LINE('--[ Вы вошли в режим просмотра (ID: ' || v_target_game_id || ') ]--');
    END IF;
    
    COMMIT;

    DECLARE
        v_active_player_id  players.player_id%TYPE;
        v_highlight_indices t_map_indices;
        v_legal_moves       t_move_list;
        v_decoded_board     VARCHAR2(128);
    BEGIN
        IF v_game.player_white_id = v_viewer_player_id THEN
            v_my_color := 'W';
        ELSIF v_game.player_black_id = v_viewer_player_id THEN
            v_my_color := 'B';
        ELSE
            v_my_color := NULL; 
        END IF;

        IF UPPER(p_wait_for_turn) = 'Y' 
        AND v_my_color IS NOT NULL
        AND v_game.current_turn != v_my_color
        AND v_game.status = 'A'
        THEN
            v_loop_start_time := SYSDATE;
            v_timeout_sec := NVL(v_game.time_limit_move_sec, 300); 

            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE('Ожидание вашего хода... (Тайм-аут: ' || v_timeout_sec || ' сек)');
            
            WHILE v_game.current_turn != v_my_color 
            AND v_game.status = 'A' 
            AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400) 
            LOOP
                dbms_session.sleep(3); 
                SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
            END LOOP;
            
            IF v_game.current_turn = v_my_color THEN
                v_wait_message := 'ВАШ ХОД!';
            ELSIF v_game.status != 'A' THEN
                v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
            ELSE 
                v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
            END IF;
        END IF;
        
        IF v_game.status NOT IN ('A', 'O', 'C') THEN
            v_error_msg := 'Игра с id = ' || v_target_game_id || ' закончена. (Статус: ' || v_game.status || ')';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('-- Используйте watch_game_replay(' || v_target_game_id || ') для просмотра.');
            
            UPDATE spectators SET left_at = SYSDATE 
            WHERE player_id = v_viewer_player_id AND game_id = v_target_game_id AND left_at IS NULL;
            COMMIT;
            
            RETURN;
        END IF;

        BEGIN
            SELECT decode_board(board_position) INTO v_decoded_board
            FROM game_moves
            WHERE game_id = v_target_game_id
            ORDER BY move_number DESC
            FETCH FIRST 1 ROW ONLY;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_decoded_board := get_initial_position(v_game.rule_id);
                IF v_decoded_board IS NULL THEN
                    v_error_msg := 'Критическая ошибка: Не удалось получить начальную позицию.';
                    p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
        END;
        
        v_board_size := SQRT(LENGTH(v_decoded_board));
        p_init_board_map(v_board_size);

        v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
        
        BEGIN
            IF v_game.status = 'A' AND v_viewer_player_id = v_active_player_id THEN
                v_legal_moves := find_all_player_moves(v_decoded_board, v_game.current_turn, v_game.rule_id);
                IF v_legal_moves.COUNT > 0 AND v_legal_moves(1).is_capture = 'Y' THEN
                    FOR i IN 1 .. v_legal_moves.COUNT LOOP
                        FOR j IN 1 .. v_legal_moves(i).path.COUNT LOOP
                            v_highlight_indices(v_legal_moves(i).path(j).end_idx) := TRUE;
                        END LOOP;
                    END LOOP;
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        
        IF v_wait_message IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE(v_wait_message);
        END IF;

        IF v_game.status = 'A' THEN
            SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
            IF v_active_player_id IS NOT NULL THEN
                SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
            END IF;
            v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
        ELSE 
            v_status_header := 'Состояние доски: ' || v_game.status || '. Ожидание игрока.';
        END IF;
        DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);

        v_printable_board := f_get_board_as_clob(v_decoded_board, v_highlight_indices);
        DBMS_OUTPUT.PUT_LINE(v_printable_board);
    END;
END print_active_board;