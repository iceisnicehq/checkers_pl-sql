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
    v_initial_position    VARCHAR2(100);
    v_encoded_position    VARCHAR2(100);
    v_status              games.status%TYPE;
    v_ai_move             VARCHAR2(50);
    v_ai_msg              VARCHAR2(1000);
    v_game_id             NUMBER;
    v_status_message      VARCHAR2(1000);
    v_my_active_game_id   NUMBER;
    v_error_msg           VARCHAR2(2000);
    v_puzzle_id_to_use    NUMBER;
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

    IF p_time_limit_move_sec IS NOT NULL AND (p_time_limit_move_sec < 30 OR p_time_limit_move_sec > 300) THEN
        v_error_msg := 'Лимит времени на ход должен быть от 30 до 300 секунд (5 минут).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_time_limit_game_sec IS NOT NULL AND (p_time_limit_game_sec < 600 OR p_time_limit_game_sec > 7200) THEN
        v_error_msg := 'Лимит времени на партию должен быть от 600 до 7200 секунд (от 10 до 120 минут).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_draw_moves_limit IS NOT NULL AND (p_draw_moves_limit < 5 OR p_draw_moves_limit > 20) THEN
        v_error_msg := 'Лимит ходов без взятий должен быть от 5 до 20.';
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
    
    IF p_ai_difficulty IS NOT NULL AND p_ai_difficulty NOT IN ('E', 'M', 'H') THEN
        v_error_msg := 'Некорректная сложность ИИ. Допустимые значения: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard).';
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

    IF p_ai_difficulty IS NOT NULL AND (p_time_limit_move_sec IS NOT NULL OR p_time_limit_game_sec IS NOT NULL) THEN
        v_error_msg := 'Игры против ИИ не могут иметь таймауты (time_limit_move_sec или time_limit_game_sec).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_puzzle_id IS NOT NULL THEN
        IF p_time_limit_move_sec IS NOT NULL OR p_time_limit_game_sec IS NOT NULL OR 
           p_draw_moves_limit IS NOT NULL OR p_enable_pos_rep_draw != 'N' OR
           p_player_color IS NOT NULL THEN
            v_error_msg := 'Задачи не могут иметь таймауты, лимиты ходов, повтор позиций или выбор цвета.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    END IF;

    IF p_daily = 'Y' THEN
        IF p_puzzle_id IS NOT NULL THEN
            v_error_msg := 'Нельзя одновременно передавать p_daily и p_puzzle_id.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        DECLARE
            v_today     DATE := TRUNC(SYSDATE);
            v_count     PLS_INTEGER;
            v_new_puzzle_id puzzles.puzzle_id%TYPE;
        BEGIN

            SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;
            
            IF v_count = 0 THEN

                BEGIN

                    SELECT puzzle_id INTO v_new_puzzle_id
                    FROM (
                        SELECT p.puzzle_id
                        FROM puzzles p
                        LEFT JOIN daily_puzzles dp ON p.puzzle_id = dp.puzzle_id AND dp.puzzle_date >= (v_today - 30)
                        WHERE p.created_by_player_id IS NULL
                        AND dp.puzzle_id IS NULL             
                        ORDER BY DBMS_RANDOM.VALUE
                    ) WHERE ROWNUM = 1;
                    
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        BEGIN
                            SELECT puzzle_id INTO v_new_puzzle_id
                            FROM (
                                SELECT puzzle_id FROM puzzles 
                                WHERE created_by_player_id IS NULL
                                ORDER BY DBMS_RANDOM.VALUE
                            ) WHERE ROWNUM = 1;
                        END;
                END;

                INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_new_puzzle_id);
                v_puzzle_id_to_use := v_new_puzzle_id;
                DBMS_OUTPUT.PUT_LINE('Daily Puzzle на сегодня успешно создан (ID: ' || v_new_puzzle_id || ').');
            ELSE

                SELECT puzzle_id INTO v_puzzle_id_to_use
                FROM daily_puzzles
                WHERE puzzle_date = v_today
                AND ROWNUM = 1;
            END IF;
        END;
    ELSE

        v_puzzle_id_to_use := p_puzzle_id;
    END IF;

    IF v_puzzle_id_to_use IS NOT NULL THEN
        DECLARE
            v_puzzle puzzles%ROWTYPE;
        BEGIN
            SELECT * INTO v_puzzle FROM puzzles WHERE puzzle_id = v_puzzle_id_to_use;
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

            DECLARE
                v_ai_difficulty_for_puzzle CHAR(1);
            BEGIN

                IF v_puzzle.created_by_player_id IS NULL THEN
                    v_ai_difficulty_for_puzzle := 'M';
                ELSE
                    v_ai_difficulty_for_puzzle := v_puzzle.difficulty_level;
                END IF;
                
                INSERT INTO games (
                    rule_id, player_white_id, player_black_id, 
                    creator_player_color,
                    status, current_turn,
                    puzzle_id, is_daily_puzzle, puzzle_status,
                    ai_difficulty
                )
                VALUES (
                    v_puzzle.rule_id, v_white_player_id, v_black_player_id, 
                    v_creator_color,
                    v_status, v_puzzle.turn_to_move,
                    v_puzzle_id_to_use, p_daily, 'p',
                    v_ai_difficulty_for_puzzle
                )
                RETURNING game_id INTO v_game_id;
            END;
            
            v_status_message := 'Вы начали задачу ID ' || v_puzzle_id_to_use || '. (ID сессии: ' || v_game_id || ').';
            p_audit_log(v_current_player_id, v_game_id, 'START_PUZZLE');
        
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Задача с ID ' || v_puzzle_id_to_use || ' не найдена.';
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
            
            BEGIN
                SELECT player_id INTO v_opponent_player_id
                FROM players
                WHERE username = UPPER(TRIM(p_opponent_username));
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_error_msg := 'Оппонент не найден.';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
            END;

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

    IF (p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL) OR (v_puzzle_id_to_use IS NOT NULL) THEN
        print_active_board(
            p_game_id => v_game_id,
            p_username => NULL,
            p_wait_for_turn => 'N'
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_game: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Неизвестная ошибка при создании игры: ' || SQLERRM);
END create_game;