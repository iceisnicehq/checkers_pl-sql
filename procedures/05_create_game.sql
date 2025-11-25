PROCEDURE create_game(
    p_opponent_username   IN VARCHAR2 DEFAULT NULL,
    p_ai_difficulty       IN CHAR     DEFAULT NULL,
    p_player_color        IN CHAR     DEFAULT NULL,
    p_rule_id             IN NUMBER   DEFAULT 1,
    p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
    p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
    p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
    p_enable_pos_rep_draw IN CHAR     DEFAULT 'N',
    p_puzzle_id           IN NUMBER   DEFAULT NULL,
    p_daily               IN CHAR     DEFAULT 'N'
) IS
    v_current_username    players.username%TYPE := USER;
    v_current_player_id   players.player_id%TYPE;
    v_opponent_player_id  players.player_id%TYPE;
    v_white_player_id     players.player_id%TYPE;
    v_black_player_id     players.player_id%TYPE;
    v_creator_color       CHAR(1);
    v_initial_position    VARCHAR2(128);
    v_encoded_position    VARCHAR2(128);
    v_status              games.status%TYPE;
    v_ai_move             VARCHAR2(50);
    v_ai_msg              VARCHAR2(1000);
    v_game_id             NUMBER;
    v_status_message      VARCHAR2(1000);
    v_my_active_game_id   NUMBER;
    v_error_msg           VARCHAR2(255);
BEGIN
    v_current_player_id := get_or_create_player_id(v_current_username);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_current_player_id;

    v_my_active_game_id := get_active_game(v_current_player_id);
    IF v_my_active_game_id IS NOT NULL THEN
        v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id;
        p_audit_log(v_current_player_id, v_my_active_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_time_limit_move_sec IS NOT NULL AND p_time_limit_move_sec <= 0 THEN
        v_error_msg := 'Лимит времени на ход должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_time_limit_game_sec IS NOT NULL AND p_time_limit_game_sec <= 0 THEN
        v_error_msg := 'Лимит времени на партию должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_draw_moves_limit IS NOT NULL AND p_draw_moves_limit <= 0 THEN
        v_error_msg := 'Лимит ходов без взятий должен быть положительным числом.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_enable_pos_rep_draw IS NOT NULL AND p_enable_pos_rep_draw NOT IN ('Y', 'N') THEN
        v_error_msg := 'Параметр enable_pos_rep_draw должен быть Y или N.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_player_color IS NOT NULL AND p_player_color NOT IN ('W', 'B') THEN
        v_error_msg := 'Цвет игрока должен быть W (белые) или B (черные).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (p_opponent_username IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_opponent_username IS NOT NULL)
    THEN
        v_error_msg := 'Конфликт параметров. Нельзя одновременно создавать Задачу, PVE и PVP.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_puzzle_id IS NOT NULL THEN
        DECLARE
            v_puzzle puzzles%ROWTYPE;
        BEGIN
            SELECT * INTO v_puzzle FROM puzzles WHERE puzzle_id = p_puzzle_id;
            v_initial_position := v_puzzle.board_position;
            v_encoded_position := encode_board(v_initial_position);
            v_status := 'A';
            
            IF v_puzzle.turn_to_move = 'W' THEN
                v_white_player_id := v_current_player_id;
                v_black_player_id := NULL;
                v_creator_color   := 'W';
            ELSE
                v_white_player_id := NULL;
                v_black_player_id := v_current_player_id;
                v_creator_color   := 'B';
            END IF;

            INSERT INTO games (
                rule_id, player_white_id, player_black_id, 
                creator_player_color,
                status, current_turn,
                puzzle_id, is_daily_puzzle, puzzle_status
            )
            VALUES (
                v_puzzle.rule_id, v_white_player_id, v_black_player_id, 
                v_creator_color,
                v_status, v_puzzle.turn_to_move,
                p_puzzle_id, p_daily, 'p'
            )
            RETURNING game_id INTO v_game_id;
            
            v_status_message := 'Вы начали задачу ID ' || p_puzzle_id || '. (ID сессии: ' || v_game_id || ').';
            p_audit_log(v_current_player_id, v_game_id, 'START_PUZZLE');
        
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Задача с ID ' || p_puzzle_id || ' не найдена.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
    ELSIF p_puzzle_id IS NULL THEN
    
        DECLARE
            v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
        BEGIN
            v_creator_color := v_color_choice;
            IF v_color_choice = 'W' THEN
                v_white_player_id := v_current_player_id;
            ELSE
                v_black_player_id := v_current_player_id;
            END IF;
        END;

        v_initial_position := get_initial_position(p_rule_id);
        IF v_initial_position IS NULL THEN
            RETURN;
        END IF;
        v_encoded_position := encode_board(v_initial_position);

        IF p_ai_difficulty IS NOT NULL THEN
            v_status := 'A';
            IF v_white_player_id IS NULL THEN v_white_player_id := NULL; ELSE v_black_player_id := NULL; END IF;

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                p_ai_difficulty, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Игра против ИИ создана (ID: ' || v_game_id || '). Вы играете за ' || CASE WHEN v_white_player_id = v_current_player_id THEN 'белых (W)' ELSE 'черных (B)' END || '.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_PVE_GAME');

            IF v_white_player_id IS NULL THEN
                v_ai_move := get_ai_move(v_encoded_position, 'W', p_rule_id, p_ai_difficulty);
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                    v_status_message := v_status_message || ' ИИ начинает с хода: ' || v_ai_move;
                END IF;
            END IF;
        
        ELSIF p_opponent_username IS NOT NULL THEN
            IF v_current_username = UPPER(p_opponent_username) THEN 
                v_error_msg := 'Нельзя вызвать самого себя.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

            DECLARE
                v_opp_active_game NUMBER := get_active_game(v_opponent_player_id);
            BEGIN
                IF v_opp_active_game IS NOT NULL THEN
                    v_error_msg := 'Игрок "' || p_opponent_username || '" уже занят в другой партии (ID: '|| v_opp_active_game ||').';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
            END;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
            v_status := 'C';

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_CHALLENGE');
            
        ELSE
            v_status := 'O';
            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_OPEN_GAME');
        END IF;
        
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(v_status_message);
    
    IF (p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL) OR (p_puzzle_id IS NOT NULL) THEN
         BEGIN
            print_active_board(
                p_game_id => v_game_id,
                p_username => NULL,
                p_wait_for_turn => 'N'
            );
         EXCEPTION
            WHEN OTHERS THEN NULL;
         END;
     END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_game: ' || SQLERRM);
        RAISE;
END create_game;
