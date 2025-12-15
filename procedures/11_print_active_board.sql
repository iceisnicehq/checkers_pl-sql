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
    v_error_msg        VARCHAR2(2000);
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

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    DECLARE
        v_existing_spectator_game_id NUMBER;
        v_closed_sessions_count NUMBER := 0;
    BEGIN
        BEGIN
            SELECT game_id INTO v_existing_spectator_game_id
            FROM spectators
            WHERE player_id = v_viewer_player_id
              AND left_at IS NULL
              AND game_id != v_target_game_id
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_existing_spectator_game_id := NULL;
        END;

        UPDATE spectators
        SET left_at = SYSDATE
        WHERE player_id = v_viewer_player_id
          AND left_at IS NULL
          AND game_id != v_target_game_id;
        
        v_closed_sessions_count := SQL%ROWCOUNT;
        
        -- Выводим сообщение о выходе из старой сессии
        IF v_closed_sessions_count > 0 THEN
            IF v_closed_sessions_count = 1 AND v_existing_spectator_game_id IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE('--[ Вы вышли из сессии просмотра игры (ID: ' || v_existing_spectator_game_id || ') ]--');
            ELSIF v_closed_sessions_count > 1 THEN
                DBMS_OUTPUT.PUT_LINE('--[ Вы вышли из ' || v_closed_sessions_count || ' сессий просмотра ]--');
            END IF;
        END IF;
    END;

    IF (v_game.player_white_id IS NULL OR v_viewer_player_id != v_game.player_white_id)
       AND (v_game.player_black_id IS NULL OR v_viewer_player_id != v_game.player_black_id)
       AND v_game.status IN ('A', 'O', 'C')
    THEN

        DECLARE
            v_existing_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_existing_count
            FROM spectators
            WHERE player_id = v_viewer_player_id
              AND game_id = v_target_game_id
              AND left_at IS NULL;
            
            IF v_existing_count = 0 THEN

                INSERT INTO spectators (player_id, game_id, joined_at)
                VALUES (v_viewer_player_id, v_target_game_id, SYSDATE);
                
                p_audit_log(v_viewer_player_id, v_target_game_id, 'SPECTATOR_JOIN');
                DBMS_OUTPUT.PUT_LINE('--[ Вы вошли в режим просмотра (ID: ' || v_target_game_id || ') ]--');
                DBMS_OUTPUT.PUT_LINE('--[ Для отмены вызовите: game_logic.stop_spectating; ]--');
            END IF;
        END;
    END IF;
    
    COMMIT;

    DECLARE
        v_active_player_id  players.player_id%TYPE;
        v_highlight_indices t_map_indices;
        v_legal_moves       t_move_list;
        v_decoded_board     VARCHAR2(100);
    BEGIN
        IF v_game.player_white_id = v_viewer_player_id THEN
            v_my_color := 'W';
        ELSIF v_game.player_black_id = v_viewer_player_id THEN
            v_my_color := 'B';
        ELSE
            v_my_color := NULL; 
        END IF;

        DECLARE
            v_waited_for_connection BOOLEAN := FALSE;
        BEGIN
            IF v_game.status IN ('O', 'C') THEN
                IF UPPER(p_wait_for_turn) = 'Y' THEN

                    v_waited_for_connection := TRUE;
                    DECLARE
                        v_initial_white_id games.player_white_id%TYPE := v_game.player_white_id;
                        v_initial_black_id games.player_black_id%TYPE := v_game.player_black_id;
                        v_connected_player_id players.player_id%TYPE;
                        v_connected_username players.username%TYPE;
                        v_connected_color CHAR(1);
                    BEGIN
                        v_loop_start_time := SYSDATE;
                        v_timeout_sec := 300;

                        WHILE v_game.status IN ('O', 'C')
                        AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400)
                        LOOP
                            SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;

                            IF (v_game.player_white_id IS NOT NULL AND v_game.player_white_id != v_initial_white_id) OR
                               (v_game.player_black_id IS NOT NULL AND v_game.player_black_id != v_initial_black_id)
                            THEN

                                IF v_game.player_white_id IS NOT NULL AND v_game.player_white_id != v_initial_white_id THEN
                                    v_connected_player_id := v_game.player_white_id;
                                    v_connected_color := 'W';
                                ELSIF v_game.player_black_id IS NOT NULL AND v_game.player_black_id != v_initial_black_id THEN
                                    v_connected_player_id := v_game.player_black_id;
                                    v_connected_color := 'B';
                                END IF;

                                BEGIN
                                    SELECT username INTO v_connected_username
                                    FROM players
                                    WHERE player_id = v_connected_player_id;
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        v_connected_username := 'Неизвестный игрок';
                                END;

                                DBMS_OUTPUT.PUT_LINE('Игрок ' || v_connected_username || ' подключился к игре (цвет: ' || 
                                                     CASE v_connected_color WHEN 'W' THEN 'белые' ELSE 'черные' END || ').');

                                SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;

                                IF v_game.player_white_id = v_viewer_player_id THEN
                                    v_my_color := 'W';
                                ELSIF v_game.player_black_id = v_viewer_player_id THEN
                                    v_my_color := 'B';
                                END IF;
                                
                                EXIT;
                            END IF;
                            
                            BEGIN
                                EXECUTE IMMEDIATE 'BEGIN DBMS_LOCK.SLEEP(3); END;';
                            EXCEPTION
                                WHEN OTHERS THEN
                                    DECLARE
                                        v_start_time DATE := SYSDATE;
                                    BEGIN
                                        WHILE (SYSDATE - v_start_time) * 86400 < 3 LOOP
                                            NULL;
                                        END LOOP;
                                    END;
                            END;
                        END LOOP;

                        IF v_game.status IN ('O', 'C') THEN
                            DBMS_OUTPUT.PUT_LINE('Тайм-аут ожидания подключения (5 минут).');
                            RETURN;
                        END IF;

                        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
                    END;
                ELSE

                    DBMS_OUTPUT.PUT_LINE('К игре еще никто не подключился.');
                    RETURN;
                END IF;
            END IF;

            IF UPPER(p_wait_for_turn) = 'Y' AND v_game.status = 'A' AND NOT v_waited_for_connection THEN

                IF v_my_color IS NOT NULL AND v_game.current_turn = v_my_color THEN

                    NULL;
                ELSE
                    DECLARE
                        v_initial_turn CHAR(1) := v_game.current_turn;
                        v_initial_move_count NUMBER;
                    BEGIN
                    SELECT COUNT(*) INTO v_initial_move_count FROM game_moves WHERE game_id = v_target_game_id;
                    
                    v_loop_start_time := SYSDATE;
                    v_timeout_sec := NVL(v_game.time_limit_move_sec, 300); 

                    WHILE v_game.status = 'A' 
                    AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400) 
                    LOOP
                        DECLARE
                            v_current_move_count NUMBER;
                        BEGIN
                            SELECT COUNT(*) INTO v_current_move_count FROM game_moves WHERE game_id = v_target_game_id;

                            IF v_my_color IS NOT NULL THEN
                                IF v_game.current_turn = v_my_color THEN
                                    EXIT;
                                END IF;

                            ELSIF v_current_move_count > v_initial_move_count OR v_game.current_turn != v_initial_turn THEN
                                EXIT;
                            END IF;
                        END;
                        
                        BEGIN
                            EXECUTE IMMEDIATE 'BEGIN DBMS_LOCK.SLEEP(3); END;';
                        EXCEPTION
                            WHEN OTHERS THEN
                                DECLARE
                                    v_start_time DATE := SYSDATE;
                                BEGIN
                                    WHILE (SYSDATE - v_start_time) * 86400 < 3 LOOP
                                        NULL;
                                    END LOOP;
                                END;
                        END;
                        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
                    END LOOP;

                    IF v_my_color IS NOT NULL THEN

                        IF v_game.current_turn = v_my_color THEN
                            v_wait_message := 'ВАШ ХОД!';
                        ELSIF v_game.status != 'A' THEN
                            v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
                        ELSE 
                            v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
                        END IF;
                    ELSE

                        DECLARE
                            v_current_move_count NUMBER;
                            v_was_move_made BOOLEAN := FALSE;
                        BEGIN
                            SELECT COUNT(*) INTO v_current_move_count FROM game_moves WHERE game_id = v_target_game_id;
                            v_was_move_made := (v_current_move_count > v_initial_move_count) OR (v_game.current_turn != v_initial_turn);
                            
                            IF v_game.status != 'A' THEN
                                v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
                            ELSIF NOT v_was_move_made AND v_game.status = 'A' THEN

                                v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
                            END IF;

                        END;
                    END IF;
                END;
                END IF;
            END IF;
        END;

        v_decoded_board := f_get_current_board_position(v_target_game_id, v_game.rule_id);

        IF v_game.status NOT IN ('A', 'O', 'C') THEN

            v_board_size := SQRT(LENGTH(v_decoded_board));
            p_init_board_map(v_board_size);

            v_printable_board := f_get_board_as_clob(v_decoded_board);
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE('ИГРА ЗАВЕРШЕНА');
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE(v_printable_board);

            DECLARE
                v_winner_id players.player_id%TYPE;
                v_loser_id  players.player_id%TYPE;
                v_winner_name players.username%TYPE;
                v_loser_name  players.username%TYPE;
            BEGIN
                IF v_game.status = 'D' THEN
                    DBMS_OUTPUT.PUT_LINE('Результат: Ничья.');
                ELSIF v_game.status = 'T' THEN
                    DBMS_OUTPUT.PUT_LINE('Результат: Игра завершена по таймауту.');
                    IF v_game.winner_player_color IS NOT NULL THEN
                        IF v_game.winner_player_color = 'W' THEN
                            v_winner_id := v_game.player_white_id;
                            v_loser_id  := v_game.player_black_id;
                        ELSE
                            v_winner_id := v_game.player_black_id;
                            v_loser_id  := v_game.player_white_id;
                        END IF;
                        
                        BEGIN 
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_winner_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        BEGIN 
                            SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_loser_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        
                        DBMS_OUTPUT.PUT_LINE('Победитель: ' || v_winner_name || ' | Проигравший: ' || v_loser_name);
                    END IF;
                ELSIF v_game.status IN ('V', 'R') THEN
                    IF v_game.winner_player_color IS NOT NULL THEN
                        IF v_game.winner_player_color = 'W' THEN
                            v_winner_id := v_game.player_white_id;
                            v_loser_id  := v_game.player_black_id;
                        ELSE
                            v_winner_id := v_game.player_black_id;
                            v_loser_id  := v_game.player_white_id;
                        END IF;
                        
                        BEGIN 
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_winner_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        BEGIN 
                            SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_loser_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        
                        IF v_game.status = 'R' THEN
                            DBMS_OUTPUT.PUT_LINE('Результат: ' || v_loser_name || ' сдался. Победитель: ' || v_winner_name || '.');
                        ELSE
                            DBMS_OUTPUT.PUT_LINE('Результат: Победа игрока ' || v_winner_name || ' над ' || v_loser_name || '.');
                        END IF;
                    END IF;
                END IF;
            END;

            IF v_game.match_id IS NOT NULL THEN
                DECLARE
                    v_match matches%ROWTYPE;
                    v_game_count NUMBER;
                    v_game_number NUMBER;
                    v_match_status CHAR(1);
                    v_next_game_id NUMBER;
                    v_is_viewer_winner BOOLEAN := FALSE;
                BEGIN
                    BEGIN
                        SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;
                        SELECT status INTO v_match_status FROM matches WHERE match_id = v_game.match_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            NULL;
                    END;

                    IF v_match.match_id IS NOT NULL THEN
                        SELECT COUNT(*) INTO v_game_count
                        FROM games
                        WHERE match_id = v_game.match_id;

                        SELECT COUNT(*) INTO v_game_number
                        FROM games
                        WHERE match_id = v_game.match_id
                          AND game_id <= v_target_game_id;

                        IF v_game.winner_player_color IS NOT NULL THEN
                            IF (v_game.winner_player_color = 'W' AND v_game.player_white_id = v_viewer_player_id) OR
                               (v_game.winner_player_color = 'B' AND v_game.player_black_id = v_viewer_player_id) THEN
                                v_is_viewer_winner := TRUE;
                            END IF;
                        END IF;

                        IF v_match_status = 'C' THEN
                            IF v_is_viewer_winner THEN
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                                DBMS_OUTPUT.PUT_LINE('ВЫ ПОБЕДИЛИ В МАТЧЕ!');
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                            ELSE
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                                DBMS_OUTPUT.PUT_LINE('МАТЧ ЗАВЕРШЕН');
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                            END IF;
                        ELSIF v_game.status IN ('V', 'R') AND v_game.winner_player_color IS NOT NULL THEN
                            IF v_is_viewer_winner THEN
                                BEGIN
                                    SELECT game_id INTO v_next_game_id
                                    FROM games
                                    WHERE match_id = v_game.match_id
                                      AND game_id > v_target_game_id
                                      AND status = 'A'
                                    ORDER BY game_id ASC
                                    FETCH FIRST 1 ROW ONLY;
                                    
                                    DBMS_OUTPUT.PUT_LINE('==================================================');
                                    DBMS_OUTPUT.PUT_LINE('Вы победили в игре ' || v_game_number || ' матча.');
                                    DBMS_OUTPUT.PUT_LINE('Начинается игра ' || (v_game_number + 1) || '...');
                                    DBMS_OUTPUT.PUT_LINE('==================================================');
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        NULL;
                                END;
                            END IF;
                        END IF;
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END IF;

            IF v_game.puzzle_id IS NULL THEN
                DBMS_OUTPUT.PUT_LINE('-- Используйте watch_game_replay(' || v_target_game_id || ') для просмотра полной партии.');
            END IF;
            
            UPDATE spectators SET left_at = SYSDATE 
            WHERE player_id = v_viewer_player_id AND game_id = v_target_game_id AND left_at IS NULL;
            COMMIT;
            
            RETURN;
        END IF;

        v_board_size := SQRT(LENGTH(v_decoded_board));
        p_init_board_map(v_board_size);

        v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;

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
        
        IF v_wait_message IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE(v_wait_message);
        END IF;

        IF v_game.status = 'A' THEN
            DECLARE
                v_white_player_name players.username%TYPE;
                v_black_player_name players.username%TYPE;
                v_players_info VARCHAR2(500) := '';
                v_ai_difficulty_to_show CHAR(1);
            BEGIN

                IF v_game.puzzle_id IS NOT NULL THEN
                    BEGIN
                        SELECT difficulty_level INTO v_ai_difficulty_to_show
                        FROM puzzles
                        WHERE puzzle_id = v_game.puzzle_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_ai_difficulty_to_show := v_game.ai_difficulty;
                    END;
                ELSE
                    v_ai_difficulty_to_show := v_game.ai_difficulty;
                END IF;
                
                IF v_game.player_white_id IS NOT NULL THEN
                    BEGIN
                        SELECT username INTO v_white_player_name FROM players WHERE player_id = v_game.player_white_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_white_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                    END;
                ELSE
                    v_white_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                END IF;
                
                IF v_game.player_black_id IS NOT NULL THEN
                    BEGIN
                        SELECT username INTO v_black_player_name FROM players WHERE player_id = v_game.player_black_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_black_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                    END;
                ELSE
                    v_black_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                END IF;
                
                v_players_info := 'Белые: ' || v_white_player_name || ' | Черные: ' || v_black_player_name;
                DBMS_OUTPUT.PUT_LINE(v_players_info);

                IF v_game.match_id IS NOT NULL THEN
                    DECLARE
                        v_match matches%ROWTYPE;
                        v_player1_id players.player_id%TYPE;
                        v_player2_id players.player_id%TYPE;
                        v_player1_wins NUMBER := 0;
                        v_player2_wins NUMBER := 0;
                        v_player1_name players.username%TYPE;
                        v_player2_name players.username%TYPE;
                        v_match_info VARCHAR2(500);
                    BEGIN
                        SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;

                        BEGIN
                            SELECT player_white_id, player_black_id
                            INTO v_player1_id, v_player2_id
                            FROM (
                                SELECT player_white_id, player_black_id
                                FROM games
                                WHERE match_id = v_game.match_id
                                ORDER BY game_id ASC
                            )
                            WHERE ROWNUM = 1;
                        EXCEPTION
                            WHEN NO_DATA_FOUND THEN
                                NULL;
                        END;

                        IF v_player1_id IS NOT NULL AND v_player2_id IS NOT NULL THEN
                            FOR r IN (
                                SELECT winner_player_color, status
                                FROM games
                                WHERE match_id = v_game.match_id
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

                            BEGIN
                                SELECT username INTO v_player1_name FROM players WHERE player_id = v_player1_id;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_player1_name := 'Игрок 1';
                            END;
                            
                            BEGIN
                                SELECT username INTO v_player2_name FROM players WHERE player_id = v_player2_id;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_player2_name := 'Игрок 2';
                            END;

                            v_match_info := 'Матч (ID: ' || v_game.match_id || ', Best of ' || v_match.games_to_win || 
                                          ') | Игра ID: ' || v_target_game_id ||
                                          ' | Счет: ' || v_player1_name || ' ' || v_player1_wins || ':' || v_player2_wins || ' ' || v_player2_name ||
                                          ' | Нужно для победы: ' || (TRUNC(v_match.games_to_win / 2) + 1) || ' игры';
                            
                            DBMS_OUTPUT.PUT_LINE(v_match_info);
                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            NULL;
                    END;
                END IF;
            END;
            SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
            IF v_active_player_id IS NOT NULL THEN
                SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
            END IF;

            IF v_game.puzzle_id IS NOT NULL THEN
                DECLARE
                    v_puzzle_difficulty CHAR(1);
                BEGIN
                    SELECT difficulty_level INTO v_puzzle_difficulty
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;
                    
                    v_status_header := 'Задача №' || v_game.puzzle_id || ' (Сложность: ' || 
                                      CASE v_puzzle_difficulty WHEN 'E' THEN 'Легкая' WHEN 'M' THEN 'Средняя' WHEN 'H' THEN 'Сложная' ELSE v_puzzle_difficulty END || 
                                      ') | Ход(#' || (v_move_count + 1) || ') игрока: ' || 
                                      NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
                END;
            ELSE
                v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
            END IF;

            IF v_game.draw_offer_status = 'O' AND v_game.draw_offered_by_color IS NOT NULL THEN
                IF v_my_color IS NOT NULL AND v_game.draw_offered_by_color != v_my_color THEN
                    v_status_header := v_status_header || ' | ВАМ ПРЕДЛОЖЕНА НИЧЬЯ (примите: A)';
                ELSIF v_my_color IS NOT NULL AND v_game.draw_offered_by_color = v_my_color THEN
                    v_status_header := v_status_header || ' | Вы предложили ничью (ожидайте ответа)';
                ELSE
                    v_status_header := v_status_header || ' | Предложение ничьей от ' || CASE v_game.draw_offered_by_color WHEN 'W' THEN 'белых' ELSE 'черных' END;
                END IF;
            END IF;

            DECLARE
                v_time_info VARCHAR2(500) := '';
                v_current_time DATE := SYSDATE;
                v_last_move_time DATE;
                v_move_elapsed_sec NUMBER;
                v_move_remaining_sec NUMBER;
                v_move_end_time DATE;
                v_white_time_remaining NUMBER;
                v_black_time_remaining NUMBER;
                v_white_end_time DATE;
                v_black_end_time DATE;
            BEGIN

                IF v_game.time_limit_game_sec IS NOT NULL AND 
                   v_game.time_white_remaining_sec IS NOT NULL AND 
                   v_game.time_black_remaining_sec IS NOT NULL THEN

                    BEGIN
                        SELECT MAX(move_timestamp) INTO v_last_move_time
                        FROM game_moves
                        WHERE game_id = v_target_game_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_last_move_time := v_game.start_time;
                    END;

                    IF v_game.current_turn = 'W' THEN
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_white_time_remaining := GREATEST(0, v_game.time_white_remaining_sec - v_move_elapsed_sec);
                        v_black_time_remaining := v_game.time_black_remaining_sec;
                    ELSE
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_white_time_remaining := v_game.time_white_remaining_sec;
                        v_black_time_remaining := GREATEST(0, v_game.time_black_remaining_sec - v_move_elapsed_sec);
                    END IF;

                    v_white_end_time := v_current_time + (v_white_time_remaining / 86400);
                    v_black_end_time := v_current_time + (v_black_time_remaining / 86400);

                    DBMS_OUTPUT.PUT_LINE('Время белых: осталось ' || 
                                       ROUND(v_white_time_remaining) || ' сек (закончится ' || 
                                       TO_CHAR(v_white_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);

                    DBMS_OUTPUT.PUT_LINE('Время черных: осталось ' || 
                                       ROUND(v_black_time_remaining) || ' сек (закончится ' || 
                                       TO_CHAR(v_black_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);
                END IF;

                IF v_game.time_limit_move_sec IS NOT NULL AND v_game.time_limit_game_sec IS NULL THEN
                    BEGIN
                        SELECT MAX(move_timestamp) INTO v_last_move_time
                        FROM game_moves
                        WHERE game_id = v_target_game_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            IF v_game.status = 'A' THEN
                                v_last_move_time := v_game.start_time;
                            ELSE
                                v_last_move_time := NULL;
                            END IF;
                    END;
                    
                    IF v_last_move_time IS NOT NULL AND v_game.status = 'A' THEN
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_move_remaining_sec := GREATEST(0, v_game.time_limit_move_sec - v_move_elapsed_sec);
                        v_move_end_time := v_last_move_time + (v_game.time_limit_move_sec / 86400);
                        
                        DBMS_OUTPUT.PUT_LINE('Время на ход: осталось ' || 
                                          ROUND(v_move_remaining_sec) || ' сек (закончится ' || 
                                          TO_CHAR(v_move_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);
                    END IF;
                END IF;
            END;
        END IF;

        IF v_game.status = 'A' THEN
            DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
        ELSIF v_game.status != 'O' THEN

            v_status_header := 'Состояние доски: ' || v_game.status || '. Ожидание игрока.';
            DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
        END IF;

        v_printable_board := f_get_board_as_clob(v_decoded_board, v_highlight_indices);
        DBMS_OUTPUT.PUT_LINE(v_printable_board);
    END;
END print_active_board;