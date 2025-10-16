CREATE OR REPLACE PACKAGE BODY C##CHECKERS_APP.game_logic AS

    -- Типы, которые должны быть видны для f_get_board_as_clob
    TYPE rec_board_field IS RECORD (idx PLS_INTEGER, notation VARCHAR2(2), row_num PLS_INTEGER, col_num PLS_INTEGER);
    TYPE map_notation_to_field IS TABLE OF rec_board_field INDEX BY VARCHAR2(2);
    g_board_map map_notation_to_field;
    TYPE r_move_step IS RECORD (start_idx PLS_INTEGER, end_idx PLS_INTEGER, captured_idx PLS_INTEGER);
    TYPE t_move_path IS TABLE OF r_move_step;
    TYPE r_move IS RECORD (notation VARCHAR2(50), path t_move_path, is_capture CHAR(1), capture_count PLS_INTEGER);
    TYPE t_move_list IS TABLE OF r_move;
    TYPE t_map_indices IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    
    FUNCTION get_my_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
            v_game_id games.game_id%TYPE;
        BEGIN
            SELECT g.game_id INTO v_game_id FROM games g
            WHERE g.status IN ('ACTIVE', 'OPEN', 'CHALLENGED')
            AND (g.player_white_id = p_user_id OR g.player_black_id = p_user_id OR g.creator_player_id = p_user_id)
            AND ROWNUM = 1;
            RETURN v_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN NULL;
    END get_my_active_game;

    FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS v_player_id players.player_id%TYPE; BEGIN BEGIN SELECT player_id INTO v_player_id FROM players WHERE username = p_username; EXCEPTION WHEN NO_DATA_FOUND THEN INSERT INTO players (username) VALUES (p_username) RETURNING player_id INTO v_player_id; END; RETURN v_player_id; END get_or_create_player_id;

    FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
        v_rule game_rules%ROWTYPE;
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        IF v_rule.rule_name = 'Русские шашки 8x8' THEN
            RETURN '+b+b+b+b' || -- Row 8
                'b+b+b+b+' || -- Row 7
                '+b+b+b+b' || -- Row 6
                '++++++++' || -- Row 5
                '++++++++' || -- Row 4
                'w+w+w+w+' || -- Row 3
                '+w+w+w+w' || -- Row 2
                'w+w+w+w+';   -- Row 1
        ELSE
            RAISE_APPLICATION_ERROR(-20100, 'Правила игры с ID=' || p_rule_id || ' не поддерживаются.');
        END IF;
    END get_initial_position;

    FUNCTION idx_to_notation(p_idx IN PLS_INTEGER) RETURN VARCHAR2 IS v_key VARCHAR2(2); BEGIN v_key := g_board_map.FIRST; WHILE v_key IS NOT NULL LOOP IF g_board_map(v_key).idx = p_idx THEN RETURN v_key; END IF; v_key := g_board_map.NEXT(v_key); END LOOP; RETURN NULL; END idx_to_notation;
    
FUNCTION find_capture_paths( p_start_idx IN PLS_INTEGER, p_board IN VARCHAR2, p_player_color IN CHAR, p_is_king IN CHAR, p_rule_id IN NUMBER, p_visited_path IN t_move_path DEFAULT t_move_path() ) RETURN t_move_list IS
        v_results t_move_list := t_move_list(); v_jump_directions SYS.ODCINUMBERLIST; v_opponent_man CHAR(1); v_opponent_king CHAR(1);
    BEGIN
        IF p_player_color = 'W' THEN v_opponent_man := c_black_man; v_opponent_king := c_black_king; ELSE v_opponent_man := c_white_man; v_opponent_king := c_white_king; END IF;
        v_jump_directions := SYS.ODCINUMBERLIST(-18, -14, 14, 18);
        FOR i IN 1 .. v_jump_directions.COUNT LOOP
            DECLARE v_jump PLS_INTEGER := v_jump_directions(i); v_land_idx PLS_INTEGER; v_capture_idx PLS_INTEGER; v_start_field rec_board_field := g_board_map(idx_to_notation(p_start_idx)); v_is_visited BOOLEAN := FALSE;
            BEGIN
                IF p_is_king = 'N' THEN
                    v_land_idx := p_start_idx + v_jump; v_capture_idx := p_start_idx + v_jump / 2;
                    IF v_land_idx BETWEEN 1 AND 64 AND ABS(v_start_field.col_num - g_board_map(idx_to_notation(v_land_idx)).col_num) = 2 THEN
                        IF SUBSTR(p_board, v_land_idx, 1) = c_empty_field AND SUBSTR(p_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN
                            FOR k IN 1 .. p_visited_path.COUNT LOOP IF p_visited_path(k).captured_idx = v_capture_idx THEN v_is_visited := TRUE; EXIT; END IF; END LOOP;
                            IF NOT v_is_visited THEN
                                DECLARE
                                    v_becomes_king CHAR(1) := 'N'; -- По умолчанию шашка не становится дамкой
                                    v_land_row PLS_INTEGER := g_board_map(idx_to_notation(v_land_idx)).row_num;
                                    v_is_promotion_square BOOLEAN := (p_player_color = 'W' AND v_land_row = 8) OR (p_player_color = 'B' AND v_land_row = 1);
                                    v_step r_move_step; v_new_path t_move_path := p_visited_path; v_sub_paths t_move_list; v_move r_move;
                                BEGIN
                                    v_step.start_idx := p_start_idx; v_step.end_idx := v_land_idx; v_step.captured_idx := v_capture_idx;
                                    v_new_path.EXTEND; v_new_path(v_new_path.LAST) := v_step;
                                    
                                    -- ПРОВЕРКА ПРАВИЛ ПРЕВРАЩЕНИЯ
                                    -- Для русских шашек (ID=1) превращение происходит немедленно
                                    IF p_rule_id = 1 AND v_is_promotion_square THEN
                                        v_becomes_king := 'Y';
                                    END IF;
                                    -- Для международных шашек (ID=2) шашка продолжает бой как простая, если может.
                                    -- Поэтому v_becomes_king остается 'N', и рекурсивный вызов будет искать ходы для простой.
                                    
                                    v_sub_paths := find_capture_paths(v_land_idx, p_board, p_player_color, v_becomes_king, p_rule_id, v_new_path);
                                    
                                    IF v_sub_paths.COUNT = 0 THEN
                                        v_move.path := v_new_path; v_move.is_capture := 'Y'; v_move.capture_count := v_new_path.COUNT;
                                        v_results.EXTEND; v_results(v_results.LAST) := v_move;
                                    ELSE
                                        FOR j IN 1 .. v_sub_paths.COUNT LOOP v_results.EXTEND; v_results(v_results.LAST) := v_sub_paths(j); END LOOP;
                                    END IF;
                                END;
                            END IF;
                        END IF;
                    END IF;
                ELSE -- Логика для дамки (остается без изменений)
                    FOR k IN 1 .. 7 LOOP v_capture_idx := p_start_idx + (v_jump / 2 * k); IF v_capture_idx NOT BETWEEN 1 AND 64 OR ABS(v_start_field.col_num - g_board_map(idx_to_notation(v_capture_idx)).col_num) != k THEN EXIT; END IF; IF SUBSTR(p_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN FOR m IN 1 .. p_visited_path.COUNT LOOP IF p_visited_path(m).captured_idx = v_capture_idx THEN v_is_visited := TRUE; EXIT; END IF; END LOOP; IF v_is_visited THEN EXIT; END IF; FOR l IN (k + 1) .. 8 LOOP v_land_idx := p_start_idx + (v_jump / 2 * l); IF v_land_idx NOT BETWEEN 1 AND 64 OR ABS(v_start_field.col_num - g_board_map(idx_to_notation(v_land_idx)).col_num) != l THEN EXIT; END IF; DECLARE v_land_field rec_board_field := g_board_map(idx_to_notation(v_land_idx)); BEGIN IF SUBSTR(p_board, v_land_idx, 1) = c_empty_field AND MOD(v_land_field.row_num + v_land_field.col_num, 2) = 0 THEN DECLARE v_step r_move_step; v_new_path t_move_path := p_visited_path; v_sub_paths t_move_list; v_move r_move; BEGIN v_step.start_idx := p_start_idx; v_step.end_idx := v_land_idx; v_step.captured_idx := v_capture_idx; v_new_path.EXTEND; v_new_path(v_new_path.LAST) := v_step; v_sub_paths := find_capture_paths(v_land_idx, p_board, p_player_color, 'Y', p_rule_id, v_new_path); IF v_sub_paths.COUNT = 0 THEN v_move.path := v_new_path; v_move.is_capture := 'Y'; v_move.capture_count := v_new_path.COUNT; v_results.EXTEND; v_results(v_results.LAST) := v_move; ELSE FOR j IN 1 .. v_sub_paths.COUNT LOOP v_results.EXTEND; v_results(v_results.LAST) := v_sub_paths(j); END LOOP; END IF; END; ELSE EXIT; END IF; END; END LOOP; EXIT; END IF; END LOOP;
                END IF;
            END;
        END LOOP;
        RETURN v_results;
    END find_capture_paths;
FUNCTION find_all_player_moves(p_board IN VARCHAR2, p_player_color IN CHAR, p_rule_id IN NUMBER) RETURN t_move_list IS
        v_all_moves t_move_list := t_move_list(); v_capture_moves t_move_list := t_move_list(); v_simple_moves t_move_list := t_move_list();
        v_player_man CHAR(1); v_player_king CHAR(1); v_max_captures PLS_INTEGER := 0;
    BEGIN
        IF p_player_color = 'W' THEN v_player_man := c_white_man; v_player_king := c_white_king; ELSE v_player_man := c_black_man; v_player_king := c_black_king; END IF;
        FOR i IN 1..64 LOOP
            DECLARE v_piece CHAR(1) := SUBSTR(p_board, i, 1); v_paths t_move_list; v_is_king CHAR(1);
            BEGIN
                IF v_piece IN (v_player_man, v_player_king) THEN
                    v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;
                    v_paths := find_capture_paths(i, p_board, p_player_color, v_is_king, p_rule_id);
                    IF v_paths.COUNT > 0 THEN
                        FOR j IN 1..v_paths.COUNT LOOP
                            v_capture_moves.EXTEND; v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                            IF v_paths(j).capture_count > v_max_captures THEN v_max_captures := v_paths(j).capture_count; END IF;
                        END LOOP;
                    END IF;
                END IF;
            END;
        END LOOP;

        IF v_capture_moves.COUNT > 0 THEN
            -- Для русских шашек (ID=1) игрок может выбрать любой вариант взятия. Возвращаем все.
            IF p_rule_id = 1 THEN
                RETURN v_capture_moves;
            ELSE -- Для международных шашек (и других) возвращаем только путь с максимальным взятием.
                FOR i IN 1..v_capture_moves.COUNT LOOP
                    IF v_capture_moves(i).capture_count = v_max_captures THEN
                        v_all_moves.EXTEND; v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                    END IF;
                END LOOP;
                RETURN v_all_moves;
            END IF;
        END IF;
        
        -- Логика для простых ходов (без взятий) остается без изменений
        FOR i IN 1..64 LOOP DECLARE v_piece CHAR(1) := SUBSTR(p_board, i, 1); v_start_not VARCHAR2(2) := idx_to_notation(i); BEGIN IF v_piece = v_player_man THEN DECLARE v_directions SYS.ODCINUMBERLIST; BEGIN IF p_player_color = 'W' THEN v_directions := SYS.ODCINUMBERLIST(-9, -7); ELSE v_directions := SYS.ODCINUMBERLIST(7, 9); END IF; FOR d IN 1..v_directions.COUNT LOOP DECLARE v_end_idx PLS_INTEGER := i + v_directions(d); v_end_not VARCHAR2(2) := idx_to_notation(v_end_idx); BEGIN IF v_end_not IS NOT NULL AND SUBSTR(p_board, v_end_idx, 1) = c_empty_field THEN IF ABS(g_board_map(v_start_not).col_num - g_board_map(v_end_not).col_num) = 1 THEN DECLARE v_move r_move; v_step r_move_step; BEGIN v_step.start_idx := i; v_step.end_idx := v_end_idx; v_step.captured_idx := NULL; v_move.path := t_move_path(v_step); v_move.is_capture := 'N'; v_move.capture_count := 0; v_simple_moves.EXTEND; v_simple_moves(v_simple_moves.LAST) := v_move; END; END IF; END IF; END; END LOOP; END; ELSIF v_piece = v_player_king THEN DECLARE v_directions SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(-9, -7, 7, 9); BEGIN FOR d IN 1..v_directions.COUNT LOOP FOR k IN 1..7 LOOP DECLARE v_end_idx PLS_INTEGER := i + (v_directions(d) * k); v_end_not VARCHAR2(2) := idx_to_notation(v_end_idx); BEGIN IF v_end_not IS NULL THEN EXIT; END IF; IF k > 1 AND ABS(g_board_map(idx_to_notation(i + (v_directions(d) * (k-1)))).col_num - g_board_map(v_end_not).col_num) != 1 THEN EXIT; END IF; IF SUBSTR(p_board, v_end_idx, 1) = c_empty_field THEN DECLARE v_move r_move; v_step r_move_step; BEGIN v_step.start_idx := i; v_step.end_idx := v_end_idx; v_step.captured_idx := NULL; v_move.path := t_move_path(v_step); v_move.is_capture := 'N'; v_move.capture_count := 0; v_simple_moves.EXTEND; v_simple_moves(v_simple_moves.LAST) := v_move; END; ELSE EXIT; END IF; END; END LOOP; END LOOP; END; END IF; END; END LOOP;
        RETURN v_simple_moves;
    END find_all_player_moves;
    
    PROCEDURE p_process_move( p_game_id IN NUMBER, p_move_notation IN VARCHAR2, p_player_id IN NUMBER, p_status_message OUT VARCHAR2 ) IS
        v_game games%ROWTYPE; v_rule game_rules%ROWTYPE; v_player_color CHAR(1); v_all_legal_moves t_move_list;
        v_chosen_move r_move; v_is_move_valid BOOLEAN := FALSE; v_new_board games.board_position%TYPE; v_move_count NUMBER;
    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
        IF v_game.player_white_id = p_player_id THEN v_player_color := 'W'; ELSE v_player_color := 'B'; END IF;
        v_all_legal_moves := find_all_player_moves(v_game.board_position, v_player_color, v_game.rule_id);
        IF v_all_legal_moves.COUNT = 0 THEN UPDATE games SET status = CASE v_player_color WHEN 'W' THEN 'BLACK_WIN' ELSE 'WHITE_WIN' END, end_time = SYSTIMESTAMP, winner_player_id = CASE v_player_color WHEN 'W' THEN v_game.player_black_id ELSE v_game.player_white_id END WHERE game_id = p_game_id; p_status_message := 'Ходов нет. Вы проиграли!'; COMMIT; RETURN; END IF;
        FOR i IN 1..v_all_legal_moves.COUNT LOOP DECLARE v_legal_move r_move := v_all_legal_moves(i); v_notation VARCHAR2(50); BEGIN v_notation := idx_to_notation(v_legal_move.path(1).start_idx); FOR j IN 1..v_legal_move.path.COUNT LOOP v_notation := v_notation || CASE v_legal_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_legal_move.path(j).end_idx); END LOOP; IF REPLACE(LOWER(p_move_notation), 'x', ':') = v_notation THEN v_chosen_move := v_legal_move; v_is_move_valid := TRUE; EXIT; END IF; END; END LOOP;
        IF NOT v_is_move_valid THEN IF v_all_legal_moves.COUNT > 0 AND v_all_legal_moves(1).is_capture = 'Y' THEN DECLARE v_error_msg VARCHAR2(2000) := 'Неверный ход. Взятие обязательно! Доступные варианты: '; v_notation_str VARCHAR2(100); BEGIN FOR i IN 1..v_all_legal_moves.COUNT LOOP v_notation_str := idx_to_notation(v_all_legal_moves(i).path(1).start_idx); FOR j IN 1..v_all_legal_moves(i).path.COUNT LOOP v_notation_str := v_notation_str || CASE v_all_legal_moves(i).is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_all_legal_moves(i).path(j).end_idx); END LOOP; v_error_msg := v_error_msg || v_notation_str || ' '; END LOOP; RAISE_APPLICATION_ERROR(-20007, RTRIM(v_error_msg)); END; ELSE RAISE_APPLICATION_ERROR(-20007, 'Нелегальный ход: "' || p_move_notation || '".'); END IF; END IF;
        
        v_new_board := v_game.board_position;
        DECLARE
            v_moving_piece CHAR(1) := SUBSTR(v_new_board, v_chosen_move.path(1).start_idx, 1);
            v_start_pos PLS_INTEGER := v_chosen_move.path(1).start_idx; v_end_pos PLS_INTEGER := v_chosen_move.path(v_chosen_move.path.LAST).end_idx; v_promoted BOOLEAN := FALSE;
        BEGIN
            v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);
            IF v_chosen_move.is_capture = 'Y' THEN FOR i IN 1..v_chosen_move.path.COUNT LOOP v_new_board := SUBSTR(v_new_board, 1, v_chosen_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, v_chosen_move.path(i).captured_idx + 1); END LOOP; END IF;
            IF v_moving_piece IN (c_white_man, c_black_man) THEN IF v_game.rule_id = 1 AND v_chosen_move.is_capture = 'Y' THEN FOR i IN 1..v_chosen_move.path.COUNT LOOP DECLARE v_intermediate_pos PLS_INTEGER := v_chosen_move.path(i).end_idx; v_intermediate_row PLS_INTEGER := g_board_map(idx_to_notation(v_intermediate_pos)).row_num; BEGIN IF (v_player_color = 'W' AND v_intermediate_row = 8) OR (v_player_color = 'B' AND v_intermediate_row = 1) THEN v_promoted := TRUE; EXIT; END IF; END; END LOOP; END IF; DECLARE v_end_row PLS_INTEGER := g_board_map(idx_to_notation(v_end_pos)).row_num; v_is_final_square_promotion BOOLEAN := (v_player_color = 'W' AND v_end_row = 8) OR (v_player_color = 'B' AND v_end_row = 1); BEGIN IF v_promoted OR v_is_final_square_promotion THEN v_moving_piece := CASE v_player_color WHEN 'W' THEN c_white_king ELSE c_black_king END; END IF; END; END IF;
            v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
        END;
        
        SELECT COUNT(*) + 1 INTO v_move_count FROM game_moves WHERE game_id = p_game_id;
        UPDATE games SET board_position = v_new_board, current_turn = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END, last_move_at = SYSTIMESTAMP, moves_since_capture = CASE v_chosen_move.is_capture WHEN 'Y' THEN 0 ELSE v_game.moves_since_capture + 1 END WHERE game_id = p_game_id;
        INSERT INTO game_moves (game_id, move_number, player_id, move_notation, is_capture, board_position) VALUES (p_game_id, v_move_count, p_player_id, p_move_notation, v_chosen_move.is_capture, v_new_board);

        -- ИЗМЕНЕНИЕ ФОРМАТА СООБЩЕНИЯ
        IF p_player_id = 0 THEN
             p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
        ELSE
             p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
        END IF;

        DECLARE v_next_turn_color CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END; v_next_player_moves t_move_list; v_opponent_pieces_exist BOOLEAN := FALSE; v_repetition_count NUMBER; BEGIN IF v_next_turn_color = 'W' THEN IF INSTR(v_new_board, c_white_man) > 0 OR INSTR(v_new_board, c_white_king) > 0 THEN v_opponent_pieces_exist := TRUE; END IF; ELSE IF INSTR(v_new_board, c_black_man) > 0 OR INSTR(v_new_board, c_black_king) > 0 THEN v_opponent_pieces_exist := TRUE; END IF; END IF; IF NOT v_opponent_pieces_exist THEN UPDATE games SET status = CASE v_player_color WHEN 'W' THEN 'WHITE_WIN' ELSE 'BLACK_WIN' END, end_time = SYSTIMESTAMP, winner_player_id = p_player_id WHERE game_id = p_game_id; p_status_message := p_status_message || ' Победа! У противника не осталось фигур.'; COMMIT; RETURN; END IF; v_next_player_moves := find_all_player_moves(v_new_board, v_next_turn_color, v_game.rule_id); IF v_next_player_moves.COUNT = 0 THEN UPDATE games SET status = CASE v_player_color WHEN 'W' THEN 'WHITE_WIN' ELSE 'BLACK_WIN' END, end_time = SYSTIMESTAMP, winner_player_id = p_player_id WHERE game_id = p_game_id; p_status_message := p_status_message || ' Победа! Противник заблокирован.'; COMMIT; RETURN; END IF; SELECT * INTO v_rule FROM game_rules WHERE rule_id = v_game.rule_id; IF v_chosen_move.is_capture = 'N' AND (v_game.moves_since_capture + 1) >= v_rule.draw_moves_limit THEN UPDATE games SET status = 'DRAW', end_time = SYSTIMESTAMP WHERE game_id = p_game_id; p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия.'; COMMIT; RETURN; END IF; IF v_rule.enable_pos_repetition_draw = 'Y' THEN SELECT COUNT(*) INTO v_repetition_count FROM game_moves WHERE game_id = p_game_id AND board_position = v_new_board; IF v_repetition_count >= 2 THEN UPDATE games SET status = 'DRAW', end_time = SYSTIMESTAMP WHERE game_id = p_game_id; p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.'; COMMIT; RETURN; END IF; END IF; END;
        COMMIT;
    END p_process_move;

    FUNCTION get_ai_move(p_board_position IN games.board_position%TYPE, p_ai_color IN games.current_turn%TYPE, p_rule_id IN games.rule_id%TYPE, p_difficulty IN games.ai_difficulty%TYPE) RETURN VARCHAR2 IS v_best_move VARCHAR2(50); v_possible_moves t_move_list; v_chosen_move r_move; BEGIN v_possible_moves := find_all_player_moves(p_board_position, p_ai_color, p_rule_id); IF v_possible_moves.COUNT > 0 THEN v_chosen_move := v_possible_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_possible_moves.COUNT + 1))); v_best_move := idx_to_notation(v_chosen_move.path(1).start_idx); FOR j IN 1..v_chosen_move.path.COUNT LOOP v_best_move := v_best_move || CASE v_chosen_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_chosen_move.path(j).end_idx); END LOOP; ELSE v_best_move := NULL; END IF; RETURN v_best_move; END get_ai_move;
     
    PROCEDURE create_game(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_player_color        IN CHAR     DEFAULT NULL,
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_ai_difficulty       IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL
    ) IS
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_initial_position    games.board_position%TYPE;
        v_status              games.status%TYPE;
        v_ai_move             VARCHAR2(50);
        v_ai_msg              VARCHAR2(1000);
        
        -- Локальные переменные вместо OUT параметров
        v_game_id             NUMBER;
        v_status_message      VARCHAR2(1000);
        
        c_ai_username CONSTANT players.username%TYPE := 'AI';
    BEGIN
        v_current_player_id := get_or_create_player_id(v_current_username);
        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_current_player_id;

        DECLARE
            v_my_active_game_id NUMBER;
        BEGIN
            v_my_active_game_id := get_my_active_game(v_current_player_id);
            IF v_my_active_game_id IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(-20001, 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id);
            END IF;
        END;

        DECLARE
            v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
        BEGIN
            IF v_color_choice = 'W' THEN v_white_player_id := v_current_player_id;
            ELSE v_black_player_id := v_current_player_id;
            END IF;
        END;

        v_initial_position := get_initial_position(p_rule_id);

        IF UPPER(p_opponent_username) = c_ai_username THEN
            -- --- ИГРА ПРОТИВ ИИ ---
            v_status := 'ACTIVE';
            IF v_white_player_id IS NULL THEN v_white_player_id := 0; ELSE v_black_player_id := 0; END IF;
            
            INSERT INTO games (creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn, board_position, ai_difficulty, time_limit_move_sec, time_limit_game_sec)
            VALUES (v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W', v_initial_position, p_ai_difficulty, p_time_limit_move_sec, p_time_limit_game_sec)
            RETURNING game_id INTO v_game_id;
            
            v_status_message := 'Игра против ИИ создана (ID: ' || v_game_id || '). Вы играете за ' || CASE WHEN v_white_player_id = v_current_player_id THEN 'белых (W)' ELSE 'черных (B)' END || '.';
            
            IF v_white_player_id = 0 THEN
                v_ai_move := get_ai_move(v_initial_position, 'W', p_rule_id, p_ai_difficulty);
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, 0, v_ai_msg);
                    v_status_message := v_status_message || ' ИИ начинает с хода: ' || v_ai_move;
                END IF;
            END IF;

        ELSIF p_opponent_username IS NOT NULL THEN
            -- --- ПРЯМОЙ ВЫЗОВ (PvP) ---
            IF v_current_username = UPPER(p_opponent_username) THEN RAISE_APPLICATION_ERROR(-20002, 'Нельзя вызвать самого себя.'); END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));
            
            DECLARE v_active_game_count NUMBER;
            BEGIN
                SELECT COUNT(*) INTO v_active_game_count FROM games WHERE status IN ('OPEN', 'CHALLENGED', 'ACTIVE') AND (player_white_id = v_opponent_player_id OR player_black_id = v_opponent_player_id OR creator_player_id = v_opponent_player_id);
                IF v_active_game_count > 0 THEN RAISE_APPLICATION_ERROR(-20020, 'Игрок "' || p_opponent_username || '" уже занят в другой партии.'); END IF;
            END;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
            v_status := 'CHALLENGED';
            
            INSERT INTO games (creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn, board_position, time_limit_move_sec, time_limit_game_sec)
            VALUES (v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W', v_initial_position, p_time_limit_move_sec, p_time_limit_game_sec)
            RETURNING game_id INTO v_game_id;
            
            v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';

        ELSE
            -- --- ОТКРЫТАЯ ИГРА (PvP) ---
            v_status := 'OPEN';
            INSERT INTO games (creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn, board_position, time_limit_move_sec, time_limit_game_sec)
            VALUES (v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W', v_initial_position, p_time_limit_move_sec, p_time_limit_game_sec)
            RETURNING game_id INTO v_game_id;
            
            v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
        END IF;

        COMMIT;
        
        -- Выводим финальное сообщение в DBMS_OUTPUT
        DBMS_OUTPUT.PUT_LINE(v_status_message);

    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END create_game;

    PROCEDURE join_game(p_game_id IN NUMBER) IS v_game games%ROWTYPE; v_player_id players.player_id%TYPE; v_active_count NUMBER; BEGIN v_player_id := get_or_create_player_id(USER); UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id; SELECT COUNT(*) INTO v_active_count FROM games WHERE status IN ('OPEN', 'CHALLENGED', 'ACTIVE') AND (player_white_id = v_player_id OR player_black_id = v_player_id OR creator_player_id = v_player_id); IF v_active_count > 0 THEN RAISE e_player_is_busy; END IF; SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE; IF v_game.status = 'CHALLENGED' THEN IF NOT (v_player_id IN (v_game.player_white_id, v_game.player_black_id) AND v_player_id != v_game.creator_player_id) THEN RAISE e_access_denied; END IF; ELSIF v_game.status = 'OPEN' THEN IF v_player_id = v_game.creator_player_id THEN RAISE e_invalid_opponent; END IF; ELSE RAISE e_game_is_over; END IF; UPDATE games SET player_white_id = NVL(v_game.player_white_id, v_player_id), player_black_id = NVL(v_game.player_black_id, v_player_id), status = 'ACTIVE', start_time = SYSTIMESTAMP WHERE game_id = p_game_id; COMMIT; END join_game;
    
    PROCEDURE resign_game IS
        v_game      games%ROWTYPE;
        v_player_id players.player_id%TYPE;
        v_game_id   NUMBER;
        v_winner_id players.player_id%TYPE;
        v_new_status games.status%TYPE;
    BEGIN
        -- 1. Находим активную игру текущего пользователя
        v_player_id := get_or_create_player_id(user);
        v_game_id := get_my_active_game(v_player_id);

        -- Если активной игры нет, просто сообщаем об этом и выходим
        IF v_game_id IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('[INFO] Нет активной партии, чтобы сдаться или отменить.');
            RETURN;
        END IF;

        -- 2. Блокируем и получаем данные игры
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

        -- 3. Проверяем статус и выполняем действие
        IF v_game.status IN ('CHALLENGED', 'OPEN') THEN
            -- Если игра еще не началась, создатель может ее отменить
            IF v_player_id = v_game.creator_player_id THEN
                DELETE FROM games WHERE game_id = v_game_id;
                DBMS_OUTPUT.PUT_LINE('[OK] Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
            ELSE
                -- Другой игрок не может отменить чужой вызов
                RAISE_APPLICATION_ERROR(-20008, 'Вы не можете отменить вызов, который вы не создавали.');
            END IF;

        ELSIF v_game.status = 'ACTIVE' THEN
            -- Если игра активна, один из игроков может сдаться
            IF v_player_id NOT IN (v_game.player_white_id, v_game.player_black_id) THEN
                RAISE_APPLICATION_ERROR(-20008, 'Вы не являетесь участником этой игры.');
            END IF;

            -- Определяем победителя
            DECLARE
                v_winner_username players.username%TYPE;
            BEGIN
                IF v_player_id = v_game.player_white_id THEN
                    v_new_status := 'BLACK_WIN';
                    v_winner_id  := v_game.player_black_id;
                ELSE
                    v_new_status := 'WHITE_WIN';
                    v_winner_id  := v_game.player_white_id;
                END IF;

                UPDATE games
                SET status             = v_new_status,
                    winner_player_id   = v_winner_id,
                    end_time           = SYSTIMESTAMP,
                    is_resigned        = 'Y'
                WHERE game_id = v_game_id;
                
                SELECT username INTO v_winner_username FROM players WHERE player_id = v_winner_id;
                DBMS_OUTPUT.PUT_LINE('[OK] Вы сдались в партии ' || v_game_id || '. Победитель: ' || v_winner_username || '.');
            END;
        ELSE
            -- Если игра уже завершена
            RAISE_APPLICATION_ERROR(-20005, 'Нельзя сдаться в уже завершенной игре.');
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END resign_game;
    FUNCTION get_game_status(p_game_id IN NUMBER) RETURN rec_game_status IS v_status rec_game_status; BEGIN SELECT g.game_id, gr.rule_name, g.status, g.current_turn, pw.username, pb.username, g.board_position, g.last_move_at, g.moves_since_capture, pwin.username INTO v_status FROM games g JOIN game_rules gr ON g.rule_id = gr.rule_id LEFT JOIN players pw ON g.player_white_id = pw.player_id LEFT JOIN players pb ON g.player_black_id = pb.player_id LEFT JOIN players pwin ON g.winner_player_id = pwin.player_id WHERE g.game_id = p_game_id; RETURN v_status; EXCEPTION WHEN NO_DATA_FOUND THEN RAISE e_game_not_found; END get_game_status;
    
    FUNCTION f_get_board_as_clob(p_board_position IN VARCHAR2, p_highlight_indices IN t_map_indices DEFAULT t_map_indices()) RETURN CLOB IS
        v_clob CLOB; v_char CHAR(1); v_linear_idx PLS_INTEGER; c_nl CONSTANT VARCHAR2(1) := CHR(10);
    BEGIN
        DBMS_LOB.createtemporary(v_clob, TRUE);
        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);
        FOR r IN REVERSE 1..8 LOOP
            DBMS_LOB.append(v_clob, r || ' |');
            FOR c IN 1..8 LOOP
                v_linear_idx := ((8 - r) * 8) + c;
                IF MOD(r + c, 2) = 0 THEN
                    v_char := SUBSTR(p_board_position, v_linear_idx, 1);
                    IF v_char = c_empty_field OR v_char IS NULL THEN
                        IF p_highlight_indices.EXISTS(v_linear_idx) THEN DBMS_LOB.append(v_clob, '[.]');
                        ELSE DBMS_LOB.append(v_clob, '[ ]');
                        END IF;
                    ELSE DBMS_LOB.append(v_clob, '[' || v_char || ']');
                    END IF;
                ELSE DBMS_LOB.append(v_clob, '   ');
                END IF;
            END LOOP;
            DBMS_LOB.append(v_clob, '| ' || r);
            DBMS_LOB.append(v_clob, c_nl);
        END LOOP;
        DBMS_LOB.append(v_clob, '--+------------------------+--' || c_nl);
        DBMS_LOB.append(v_clob, '  | A  B  C  D  E  F  G  H |' || c_nl);
        RETURN v_clob;
    END f_get_board_as_clob;

    PROCEDURE start_replay_session(p_game_id IN NUMBER) IS v_player_id players.player_id%type; v_game_status games.status%type; v_max_moves number; v_seq_name varchar2(64); v_job_name varchar2(64); begin v_player_id := get_or_create_player_id(user); UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id; select status into v_game_status from games where game_id = p_game_id; if v_game_status in ( 'ACTIVE', 'OPEN', 'CHALLENGED' ) then raise_application_error(-20010, 'Нельзя просматривать активную партию.'); end if; select count(*) into v_max_moves from game_moves where game_id = p_game_id; if v_max_moves = 0 then raise_application_error(-20011, 'В этой партии нет ходов для просмотра.'); end if; v_seq_name := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id; v_job_name := 'DROP_REPLAY_SEQ_' || p_game_id || '_' || v_player_id; BEGIN EXECUTE IMMEDIATE 'DROP SEQUENCE ' || v_seq_name; EXCEPTION WHEN OTHERS THEN NULL; END; BEGIN DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END; EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seq_name || ' START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE ' || v_max_moves || ' NOCYCLE NOCACHE'; dbms_scheduler.create_job( job_name => v_job_name, job_type => 'PLSQL_BLOCK', job_action => 'BEGIN EXECUTE IMMEDIATE ''DROP SEQUENCE ' || v_seq_name || '''; END;', start_date => systimestamp + interval '30' minute, enabled => true, auto_drop => true, comments => 'Drop replay sequence for game ' || p_game_id || ' and player ' || v_player_id ); commit; end start_replay_session;
    PROCEDURE show_next_replay_move(p_game_id IN NUMBER, p_moves_to_show IN NUMBER DEFAULT 1) IS v_player_id players.player_id%TYPE; v_seq_name VARCHAR2(64); v_move_num NUMBER; v_cursor SYS_REFCURSOR; v_game_id_fetch game_moves.game_id%TYPE; v_move_number_fetch game_moves.move_number%TYPE; v_username_fetch players.username%TYPE; v_move_notation_fetch game_moves.move_notation%TYPE; v_is_capture_fetch game_moves.is_capture%TYPE; v_move_ts_fetch game_moves.move_timestamp%TYPE; v_board_pos_fetch games.board_position%TYPE; v_color_str VARCHAR2(10); BEGIN v_player_id := get_or_create_player_id(USER); UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id; v_seq_name := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id; FOR i IN 1..p_moves_to_show LOOP BEGIN BEGIN EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num; EXCEPTION WHEN OTHERS THEN IF SQLCODE = -8004 THEN RAISE e_replay_finished; ELSE RAISE e_replay_session_not_started; END IF; END; OPEN v_cursor FOR SELECT * FROM v_game_protocol WHERE game_id = p_game_id AND move_number = v_move_num; FETCH v_cursor INTO v_game_id_fetch, v_move_number_fetch, v_username_fetch, v_move_notation_fetch, v_is_capture_fetch, v_move_ts_fetch, v_board_pos_fetch; IF v_cursor%FOUND THEN CLOSE v_cursor; v_color_str := CASE WHEN MOD(v_move_number_fetch, 2) = 1 THEN '(Белые)' ELSE '(Черные)' END; DBMS_OUTPUT.PUT_LINE('---'); DBMS_OUTPUT.PUT_LINE( 'Ход ' || v_move_number_fetch || ' ' || RPAD(v_username_fetch, 20) || ' ' || RPAD(v_color_str, 10) || ' : ' || v_move_notation_fetch ); DBMS_OUTPUT.PUT_LINE(f_get_board_as_clob(v_board_pos_fetch)); ELSE CLOSE v_cursor; EXIT; END IF; EXCEPTION WHEN e_replay_finished THEN DBMS_OUTPUT.PUT_LINE('--[ КОНЕЦ ПАРТИИ ]-- Для повторного просмотра вызовите start_replay_session.'); IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF; EXIT; END; END LOOP; EXCEPTION WHEN e_replay_session_not_started THEN DBMS_OUTPUT.PUT_LINE('[ВНИМАНИЕ] Сессия просмотра не начата. Вызовите game_logic.start_replay_session(' || p_game_id || ');'); WHEN OTHERS THEN IF v_cursor%ISOPEN THEN CLOSE v_cursor; END IF; RAISE; END show_next_replay_move;
    
    PROCEDURE print_board(
        p_game_id     IN NUMBER   DEFAULT NULL,
        p_username    IN VARCHAR2 DEFAULT NULL,
        p_hide_header IN BOOLEAN  DEFAULT FALSE -- Новый параметр
    ) IS
        v_target_game_id    games.game_id%TYPE;
        v_target_user_id    players.player_id%TYPE;
        v_target_username   players.username%TYPE;
        v_game              games%ROWTYPE;
        v_printable_board   CLOB;
        v_status_header     VARCHAR2(200);
        v_player_username   players.username%TYPE;
        v_move_count        NUMBER;
        c_nl                CONSTANT VARCHAR2(1) := CHR(10);
    BEGIN
        IF p_game_id IS NOT NULL AND p_username IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(-20015, 'Для поиска передайте процедуре только один параметр (имя пользователя или id игры).');
        END IF;

        IF p_game_id IS NOT NULL THEN
            v_target_game_id := p_game_id;
        ELSIF p_username IS NOT NULL THEN
            v_target_username := UPPER(p_username);
            BEGIN
                SELECT player_id INTO v_target_user_id FROM players WHERE username = v_target_username;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20016, 'Пользователя "' || p_username || '" не существует.');
            END;
            v_target_game_id := get_my_active_game(v_target_user_id);
            IF v_target_game_id IS NULL THEN
                RAISE_APPLICATION_ERROR(-20017, 'У пользователя "' || p_username || '" не найдено активных сессий.');
            END IF;
        ELSE
            v_target_user_id := get_or_create_player_id(USER);
            v_target_game_id := get_my_active_game(v_target_user_id);
            IF v_target_game_id IS NULL THEN
                RAISE_APPLICATION_ERROR(-20017, 'У вас нет активных игр.');
            END IF;
        END IF;

        BEGIN
            SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20003, 'Игры с id = ' || v_target_game_id || ' не существует.');
        END;

        IF v_game.status NOT IN ('ACTIVE', 'OPEN', 'CHALLENGED') THEN
            RAISE_APPLICATION_ERROR(-20018, 'Игра с id = ' || v_target_game_id || ' закончена, вы можете посмотреть повтор игры.');
        END IF;
        
        DECLARE
            v_active_player_id players.player_id%TYPE;
            v_viewer_player_id players.player_id%TYPE;
            v_highlight_indices t_map_indices;
            v_legal_moves t_move_list;
        BEGIN
            v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;
            v_viewer_player_id := get_or_create_player_id(USER);

            IF v_game.status = 'ACTIVE' AND v_viewer_player_id = v_active_player_id THEN
                v_legal_moves := find_all_player_moves(v_game.board_position, v_game.current_turn, v_game.rule_id);
                IF v_legal_moves.COUNT > 0 AND v_legal_moves(1).is_capture = 'Y' THEN
                    FOR i IN 1..v_legal_moves.COUNT LOOP
                        v_highlight_indices(v_legal_moves(i).path(v_legal_moves(i).path.LAST).end_idx) := TRUE;
                    END LOOP;
                END IF;
            END IF;
            
            -- Проверяем флаг, чтобы решить, печатать ли заголовок
            IF NOT p_hide_header THEN
                IF v_game.status = 'ACTIVE' THEN
                    SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
                    IF v_active_player_id IS NOT NULL THEN
                        SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
                    ELSE
                        v_player_username := '(ожидание)';
                    END IF;
                    v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || v_player_username || ' (' || v_game.current_turn || ')';
                ELSE
                     v_status_header := 'Состояние доски: ' || v_game.status;
                END IF;
                DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
            END IF;
            
            v_printable_board := f_get_board_as_clob(v_game.board_position, v_highlight_indices);
            DBMS_OUTPUT.PUT_LINE(v_printable_board);
        END;
    END print_board;

    PROCEDURE make_move(
        p_move_notation  IN VARCHAR2
    ) IS
        v_game_id   NUMBER;
        v_game      games%ROWTYPE;
        v_player_id players.player_id%TYPE;
        v_human_msg VARCHAR2(1000);
        v_ai_msg    VARCHAR2(1000);
        c_nl        CONSTANT VARCHAR2(1) := CHR(10);
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        v_game_id := get_my_active_game(v_player_id);
        IF v_game_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20017, 'У вас нет активных игр, чтобы сделать ход.');
        END IF;

        UPDATE players SET last_activity_at = SYSTIMESTAMP WHERE player_id = v_player_id;
        SELECT * INTO v_game FROM games WHERE game_id = v_game_id;
        IF v_game.status NOT IN ('ACTIVE') THEN RAISE e_game_is_over; END IF;
        IF v_game.player_white_id != v_player_id AND v_game.player_black_id != v_player_id THEN RAISE e_access_denied; END IF;
        IF (v_game.current_turn = 'W' AND v_game.player_white_id != v_player_id) OR (v_game.current_turn = 'B' AND v_game.player_black_id != v_player_id) THEN RAISE e_not_your_turn; END IF;

        p_process_move(v_game_id, p_move_notation, v_player_id, v_human_msg);
        DBMS_OUTPUT.PUT_LINE(v_human_msg);
        
        BEGIN
            -- Вызываем print_board со скрытым заголовком
            print_board(p_game_id => v_game_id, p_hide_header => TRUE);
        EXCEPTION
            WHEN OTHERS THEN NULL; 
        END;

        DECLARE
            v_next_game_state   games%ROWTYPE;
            v_ai_move           VARCHAR2(50);
        BEGIN
            SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;
            
            IF v_next_game_state.status = 'ACTIVE' AND v_next_game_state.ai_difficulty IS NOT NULL AND
               ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id = 0) OR
                (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id = 0))
            THEN
                v_ai_move := get_ai_move(v_next_game_state.board_position, v_next_game_state.current_turn, v_next_game_state.rule_id, v_next_game_state.ai_difficulty);
                
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, 0, v_ai_msg);
                    
                    DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                    BEGIN
                        -- И здесь тоже вызываем print_board со скрытым заголовком
                        print_board(p_game_id => v_game_id, p_hide_header => TRUE);
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                END IF;
            END IF;
        END;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END make_move;

    FUNCTION get_possible_moves(p_game_id IN NUMBER) RETURN SYS_REFCURSOR IS v_cursor SYS_REFCURSOR; v_game games%ROWTYPE; v_player_id players.player_id%TYPE; v_player_color CHAR(1); v_all_legal_moves t_move_list; v_notations game_logic.tbl_move_notation := game_logic.tbl_move_notation(); v_notation_str VARCHAR2(100); BEGIN SELECT * INTO v_game FROM games WHERE game_id = p_game_id; IF v_game.status != 'ACTIVE' THEN RAISE e_game_is_over; END IF; v_player_id := get_or_create_player_id(USER); IF v_game.player_white_id = v_player_id THEN v_player_color := 'W'; ELSIF v_game.player_black_id = v_player_id THEN v_player_color := 'B'; ELSE RAISE e_access_denied; END IF; IF v_game.current_turn != v_player_color THEN RAISE e_not_your_turn; END IF; v_all_legal_moves := find_all_player_moves(v_game.board_position, v_player_color, v_game.rule_id); FOR i IN 1..v_all_legal_moves.COUNT LOOP v_notation_str := idx_to_notation(v_all_legal_moves(i).path(1).start_idx); FOR j IN 1..v_all_legal_moves(i).path.COUNT LOOP v_notation_str := v_notation_str || CASE v_all_legal_moves(i).is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_all_legal_moves(i).path(j).end_idx); END LOOP; v_notations.EXTEND; v_notations(v_notations.LAST) := game_logic.rec_move_notation(v_notation_str); END LOOP; OPEN v_cursor FOR SELECT * FROM TABLE(v_notations); RETURN v_cursor; EXCEPTION WHEN NO_DATA_FOUND THEN RAISE e_game_not_found; END get_possible_moves;
    FUNCTION cleanup_stale_games(p_timeout_minutes IN NUMBER) RETURN NUMBER IS v_cleaned_count NUMBER := 0; BEGIN FOR r IN ( SELECT game_id, status, player_white_id, player_black_id, current_turn FROM games WHERE status IN ('ACTIVE', 'OPEN', 'CHALLENGED') AND last_move_at < (SYSTIMESTAMP - NUMTODSINTERVAL(p_timeout_minutes, 'MINUTE')) FOR UPDATE ) LOOP DECLARE v_new_status games.status%TYPE; v_winner_id games.winner_player_id%TYPE; BEGIN IF r.status IN ('OPEN', 'CHALLENGED') THEN v_new_status := 'TIMEOUT'; v_winner_id := NULL; ELSE v_new_status := CASE r.current_turn WHEN 'W' THEN 'BLACK_WIN' ELSE 'WHITE_WIN' END; v_winner_id := CASE r.current_turn WHEN 'W' THEN r.player_black_id ELSE r.player_white_id END; END IF; UPDATE games SET status = v_new_status, winner_player_id = v_winner_id, end_time = SYSTIMESTAMP WHERE game_id = r.game_id; v_cleaned_count := v_cleaned_count + 1; END; END LOOP; COMMIT; RETURN v_cleaned_count; END cleanup_stale_games;

    BEGIN -- Package Initialization Block
        FOR r IN 1..8 LOOP
            FOR c IN 1..8 LOOP
                DECLARE
                    v_idx       PLS_INTEGER := ((8 - r) * 8) + c;
                    v_notation  VARCHAR2(2)  := CHR(ASCII('a') + c - 1) || r;
                BEGIN
                    g_board_map(v_notation).idx := v_idx;
                    g_board_map(v_notation).notation := v_notation;
                    g_board_map(v_notation).row_num := r;
                    g_board_map(v_notation).col_num := c;
                END;
            END LOOP;
        END LOOP;
    END game_logic;
/