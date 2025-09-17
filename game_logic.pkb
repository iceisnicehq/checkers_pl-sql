CREATE OR REPLACE PACKAGE BODY C##CHECKERS_APP.game_logic AS

    -- =========================================================================
    -- == ПРИВАТНЫЕ ТИПЫ, ПЕРЕМЕННЫЕ И ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
    -- =========================================================================
    TYPE rec_board_field IS RECORD (
        idx         PLS_INTEGER,
        notation    VARCHAR2(2),
        row_num     PLS_INTEGER,
        col_num     PLS_INTEGER
    );
    TYPE map_notation_to_field IS TABLE OF rec_board_field INDEX BY VARCHAR2(2);
    g_board_map map_notation_to_field;

    TYPE r_move_step IS RECORD ( -- Один шаг в маршруте (например, с c3 на e5)
        start_idx       PLS_INTEGER,
        end_idx         PLS_INTEGER,
        captured_idx    PLS_INTEGER -- NULL, если это не взятие
    );
    TYPE t_move_path IS TABLE OF r_move_step; -- Полный маршрут (может состоять из нескольких шагов, e.g., c3:e5:g7)

    TYPE r_move IS RECORD (
        notation        VARCHAR2(50),
        path            t_move_path,
        is_capture      CHAR(1), -- <<< ИСПРАВЛЕНО (Y/N)
        capture_count   PLS_INTEGER
    );
    TYPE t_move_list IS TABLE OF r_move;

    FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
        v_player_id players.player_id%TYPE;
    BEGIN
        BEGIN
            SELECT player_id INTO v_player_id FROM players WHERE username = p_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO players (username) VALUES (p_username) RETURNING player_id INTO v_player_id;
                INSERT INTO audit_log (player_id, event_type, event_details)
                VALUES (v_player_id, 'PLAYER_REGISTERED', 'New player (' || p_username || ') created.');
        END;
        RETURN v_player_id;
    END get_or_create_player_id;

    FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
        v_board_position games.board_position%TYPE;
        v_rule           game_rules%ROWTYPE;
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        IF v_rule.rule_name = 'Русские шашки 8x8' THEN
            v_board_position := RPAD(c_black_man, 12, c_black_man) || RPAD(c_empty_field, 8, c_empty_field) || RPAD(c_white_man, 12, c_white_man);
        ELSE
            RAISE_APPLICATION_ERROR(-20100, 'Правила игры с ID=' || p_rule_id || ' не поддерживаются.');
        END IF;
        RETURN v_board_position;
    END get_initial_position;
    
    FUNCTION idx_to_notation(p_idx IN PLS_INTEGER) RETURN VARCHAR2 IS
        v_key VARCHAR2(2); -- Переменная для хранения ключа (нотации)
    BEGIN
        -- Начинаем с первого ключа в ассоциативном массиве
        v_key := g_board_map.FIRST;
        
        -- Цикл, который продолжается, пока есть ключи
        WHILE v_key IS NOT NULL LOOP
            -- Проверяем, совпадает ли поле 'idx' в записи по текущему ключу с искомым p_idx
            IF g_board_map(v_key).idx = p_idx THEN
                -- Если совпало, мы нашли нужную нотацию. Возвращаем ключ.
                RETURN v_key;
            END IF;
            -- Переходим к следующему ключу в массиве
            v_key := g_board_map.NEXT(v_key);
        END LOOP;
        
        -- Если цикл завершился, а совпадение не найдено, возвращаем NULL
        RETURN NULL;
    END idx_to_notation;

    /**
     * Рекурсивная функция для поиска всех возможных цепочек взятий из заданной точки.
     */
    FUNCTION find_capture_paths(
        p_start_idx     IN PLS_INTEGER,
        p_board         IN VARCHAR2,
        p_player_color  IN CHAR,
        p_is_king       IN CHAR, -- 'Y'/'N'
        p_visited_path  IN t_move_path DEFAULT t_move_path()
    ) RETURN t_move_list IS
        v_results       t_move_list := t_move_list();
        v_jump_directions SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST(-9, -7, 7, 9); -- UpLeft, UpRight, DownLeft, DownRight
        v_opponent_man  CHAR(1);
        v_opponent_king CHAR(1);
    BEGIN
        IF p_player_color = 'W' THEN
            v_opponent_man := c_black_man; v_opponent_king := c_black_king;
        ELSE
            v_opponent_man := c_white_man; v_opponent_king := c_white_king;
        END IF;

        FOR i IN 1..v_jump_directions.COUNT LOOP
            DECLARE
                v_jump          PLS_INTEGER := v_jump_directions(i);
                v_land_idx      PLS_INTEGER := p_start_idx + v_jump;
                v_capture_idx   PLS_INTEGER;
                v_step          r_move_step;
                v_is_visited    CHAR(1) := 'N';
                v_start_not     VARCHAR2(2) := idx_to_notation(p_start_idx);
                v_land_not      VARCHAR2(2) := idx_to_notation(v_land_idx);
            BEGIN
                IF v_land_not IS NOT NULL AND ABS(g_board_map(v_start_not).col_num - g_board_map(v_land_not).col_num) = 2 THEN
                    
                    -- --- ВОТ ОКОНЧАТЕЛЬНОЕ ИСПРАВЛЕНИЕ ---
                    -- Возвращаемся к надежной логике, основанной на направлении прыжка, а не на неверной математике.
                    IF v_jump = -9 THEN v_capture_idx := p_start_idx - 5; -- Прыжок Вверх-Влево, бьем шашку на -5
                    ELSIF v_jump = -7 THEN v_capture_idx := p_start_idx - 4; -- Прыжок Вверх-Вправо, бьем шашку на -4
                    ELSIF v_jump = 7 THEN v_capture_idx := p_start_idx + 3; -- Прыжок Вниз-Влево, бьем шашку на +3
                    ELSIF v_jump = 9 THEN v_capture_idx := p_start_idx + 4; -- Прыжок Вниз-Вправо, бьем шашку на +4
                    END IF;

                    IF idx_to_notation(v_capture_idx) IS NOT NULL THEN
                        IF (SUBSTR(p_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king)) AND (SUBSTR(p_board, v_land_idx, 1) = c_empty_field) THEN
                            FOR k IN 1..p_visited_path.COUNT LOOP IF p_visited_path(k).captured_idx = v_capture_idx THEN v_is_visited := 'Y'; EXIT; END IF; END LOOP;

                            IF v_is_visited = 'N' THEN
                                v_step.start_idx := p_start_idx; v_step.end_idx := v_land_idx; v_step.captured_idx := v_capture_idx;
                                DECLARE
                                    v_new_path t_move_path := p_visited_path;
                                    v_sub_paths t_move_list; v_move r_move;
                                BEGIN
                                    v_new_path.EXTEND; v_new_path(v_new_path.LAST) := v_step;
                                    v_sub_paths := find_capture_paths(v_land_idx, p_board, p_player_color, p_is_king, v_new_path);
                                    IF v_sub_paths.COUNT = 0 THEN
                                        v_move.path := v_new_path; v_move.is_capture := 'Y'; v_move.capture_count := v_new_path.COUNT;
                                        v_results.EXTEND; v_results(v_results.LAST) := v_move;
                                    ELSE
                                        FOR j IN 1..v_sub_paths.COUNT LOOP v_results.EXTEND; v_results(v_results.LAST) := v_sub_paths(j); END LOOP;
                                    END IF;
                                END;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END;
        END LOOP;
        RETURN v_results;
    END find_capture_paths;

    /**
     * Находит ВСЕ возможные ходы для игрока (и взятия, и простые).
     */

    FUNCTION find_all_player_moves(p_board IN VARCHAR2, p_player_color IN CHAR) RETURN t_move_list IS
        v_all_moves         t_move_list := t_move_list();
        v_capture_moves     t_move_list := t_move_list();
        v_simple_moves      t_move_list := t_move_list();
        v_player_man        CHAR(1); v_player_king       CHAR(1);
        v_max_captures      PLS_INTEGER := 0;
    BEGIN
        IF p_player_color = 'W' THEN v_player_man := c_white_man; v_player_king := c_white_king;
        ELSE v_player_man := c_black_man; v_player_king := c_black_king; END IF;

        FOR i IN 1..32 LOOP
            DECLARE v_piece CHAR(1) := SUBSTR(p_board, i, 1); v_paths t_move_list; v_is_king CHAR(1);
            BEGIN
                IF v_piece IN (v_player_man, v_player_king) THEN
                    IF v_piece = v_player_king THEN v_is_king := 'Y'; ELSE v_is_king := 'N'; END IF;
                    v_paths := find_capture_paths(i, p_board, p_player_color, v_is_king);
                    IF v_paths.COUNT > 0 THEN
                        FOR j IN 1..v_paths.COUNT LOOP
                            v_capture_moves.EXTEND; v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                            IF v_paths(j).capture_count > v_max_captures THEN v_max_captures := v_paths(j).capture_count; END IF;
                        END LOOP;
                    END IF;
                END IF;
            END;
        END LOOP;

        IF v_max_captures > 0 THEN
            FOR i IN 1..v_capture_moves.COUNT LOOP
                IF v_capture_moves(i).capture_count = v_max_captures THEN v_all_moves.EXTEND; v_all_moves(v_all_moves.LAST) := v_capture_moves(i); END IF;
            END LOOP;
            RETURN v_all_moves;
        END IF;

        FOR i IN 1..32 LOOP
            DECLARE
                v_piece CHAR(1) := SUBSTR(p_board, i, 1); v_directions SYS.ODCINUMBERLIST;
                v_move r_move; v_step r_move_step; v_start_not VARCHAR2(2) := idx_to_notation(i);
            BEGIN
                IF v_piece = v_player_man THEN
                    IF p_player_color = 'W' THEN
                        v_directions := SYS.ODCINUMBERLIST(-4, -3);
                    ELSE
                        -- >>> ВОТ ГЛАВНОЕ ИСПРАВЛЕНИЕ <<<
                        v_directions := SYS.ODCINUMBERLIST(3, 4); -- Было (4, 5)
                    END IF;
                    FOR d IN 1..v_directions.COUNT LOOP
                        DECLARE v_end_idx PLS_INTEGER := i + v_directions(d); v_end_not VARCHAR2(2) := idx_to_notation(v_end_idx);
                        BEGIN
                            IF v_end_not IS NOT NULL THEN
                                IF ABS(g_board_map(v_start_not).col_num - g_board_map(v_end_not).col_num) = 1 AND SUBSTR(p_board, v_end_idx, 1) = c_empty_field THEN
                                    v_step.start_idx := i; v_step.end_idx := v_end_idx; v_step.captured_idx := NULL;
                                    v_move.path := t_move_path();
                                    v_move.path.EXTEND;
                                    v_move.path(1) := v_step;
                                    v_move.is_capture := 'N'; v_move.capture_count := 0;
                                    v_simple_moves.EXTEND; v_simple_moves(v_simple_moves.LAST) := v_move;
                                END IF;
                            END IF;
                        END;
                    END LOOP;
                END IF;
            END;
        END LOOP;
        RETURN v_simple_moves;
    END find_all_player_moves;
    -- =========================================================================
    -- == ПУБЛИЧНЫЕ ПРОЦЕДУРЫ И ФУНКЦИИ
    -- =========================================================================

    PROCEDURE create_game(
        p_opponent_username   IN  VARCHAR2 DEFAULT NULL, p_player_color IN CHAR DEFAULT NULL, p_rule_id IN NUMBER DEFAULT 1,
        p_time_limit_move_sec IN  NUMBER   DEFAULT NULL, p_time_limit_game_sec IN NUMBER DEFAULT NULL,
        p_game_id OUT NUMBER, p_status_message OUT VARCHAR2
    ) IS
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_active_game_count   NUMBER;
        v_initial_position    games.board_position%TYPE;
        v_status              games.status%TYPE;
        v_error_details       VARCHAR2(1000);
        v_challenges_msg      VARCHAR2(500);
        v_open_games_count    NUMBER;
    BEGIN
        v_current_player_id := get_or_create_player_id(v_current_username);
        SELECT COUNT(*) INTO v_active_game_count FROM games
        WHERE (status = 'ACTIVE' AND (player_white_id = v_current_player_id OR player_black_id = v_current_player_id))
           OR (status = 'WAITING' AND creator_player_id = v_current_player_id);
        IF v_active_game_count > 0 THEN RAISE e_player_is_busy; END IF;
        IF p_player_color = 'W' THEN v_white_player_id := v_current_player_id; ELSIF p_player_color = 'B' THEN v_black_player_id := v_current_player_id;
        ELSE IF dbms_random.value < 0.5 THEN v_white_player_id := v_current_player_id; ELSE v_black_player_id := v_current_player_id; END IF; END IF;
        IF p_opponent_username IS NOT NULL THEN
            IF v_current_username = UPPER(p_opponent_username) THEN RAISE e_invalid_opponent; END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));
            SELECT COUNT(*) INTO v_active_game_count FROM games WHERE status = 'ACTIVE' AND (player_white_id = v_opponent_player_id OR player_black_id = v_opponent_player_id);
            IF v_active_game_count > 0 THEN RAISE e_player_is_busy; END IF;
            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
        END IF;
        v_initial_position := get_initial_position(p_rule_id);
        v_status := 'WAITING';
        INSERT INTO games ( creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn, board_position, time_limit_move_sec, time_limit_game_sec
        ) VALUES ( v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W', v_initial_position, p_time_limit_move_sec, p_time_limit_game_sec
        ) RETURNING game_id INTO p_game_id;
        FOR r IN (SELECT creator_username FROM v_open_games WHERE challenged_player = v_current_username) LOOP v_challenges_msg := v_challenges_msg || r.creator_username || ', '; END LOOP;
        SELECT COUNT(*) INTO v_open_games_count FROM v_open_games WHERE challenge_type = 'Open Challenge' AND creator_username != v_current_username;
        p_status_message := '[OK] Ваш вызов создан. Game ID: ' || p_game_id || '.';
        IF v_challenges_msg IS NOT NULL THEN p_status_message := p_status_message || CHR(10) || '[INFO] Вас ожидают прямые вызовы от: ' || RTRIM(v_challenges_msg, ', ') || '.'; END IF;
        IF v_open_games_count > 0 THEN p_status_message := p_status_message || CHR(10) || '[INFO] В лобби есть еще ' || v_open_games_count || ' открытых игр.'; END IF;
        COMMIT;
    EXCEPTION WHEN e_invalid_opponent OR e_player_is_busy THEN ROLLBACK; RAISE;
            INSERT INTO audit_log (player_id, event_type, event_details) VALUES (v_current_player_id, 'CREATE_GAME_ERROR', v_error_details);
            COMMIT; RAISE;
    END create_game;

    PROCEDURE join_game(p_game_id IN NUMBER) IS
        v_game          games%ROWTYPE;
        v_player_id     players.player_id%TYPE;
        v_active_count  NUMBER;
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        SELECT COUNT(*) INTO v_active_count FROM games WHERE status = 'ACTIVE' AND (player_white_id = v_player_id OR player_black_id = v_player_id);
        IF v_active_count > 0 THEN RAISE e_player_is_busy; END IF;
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
        IF v_game.status != 'WAITING' THEN RAISE e_game_is_over; END IF;
        IF v_player_id = v_game.creator_player_id THEN RAISE e_invalid_opponent; END IF;
        IF v_game.player_white_id IS NOT NULL AND v_game.player_black_id IS NOT NULL THEN
            IF v_player_id != v_game.player_white_id AND v_player_id != v_game.player_black_id THEN RAISE e_access_denied; END IF;
        END IF;
        UPDATE games SET player_white_id = NVL(v_game.player_white_id, v_player_id), player_black_id = NVL(v_game.player_black_id, v_player_id), status = 'ACTIVE', start_time = SYSTIMESTAMP
        WHERE game_id = p_game_id;
        COMMIT;
    END join_game;

    PROCEDURE make_move(
        p_game_id         IN  NUMBER,
        p_move_notation   IN  VARCHAR2,
        p_status_message  OUT VARCHAR2
    ) IS
        v_game              games%ROWTYPE;
        v_player_id         players.player_id%TYPE;
        v_player_color      CHAR(1);
        v_all_legal_moves   t_move_list;
        v_chosen_move       r_move;
        v_is_move_valid     CHAR(1) := 'N'; -- --- ИЗМЕНЕНО ---
        v_new_board         games.board_position%TYPE;
        v_move_count        NUMBER;
        v_error_details     VARCHAR2(1000);
    BEGIN
        BEGIN SELECT * INTO v_game FROM games WHERE game_id = p_game_id; EXCEPTION WHEN NO_DATA_FOUND THEN RAISE e_game_not_found; END;
        IF v_game.status != 'ACTIVE' THEN RAISE e_game_is_over; END IF;
        v_player_id := get_or_create_player_id(USER);
        IF v_game.player_white_id = v_player_id THEN v_player_color := 'W'; ELSIF v_game.player_black_id = v_player_id THEN v_player_color := 'B'; ELSE RAISE e_access_denied; END IF;
        IF v_game.current_turn != v_player_color THEN RAISE e_not_your_turn; END IF;

        v_all_legal_moves := find_all_player_moves(v_game.board_position, v_player_color);

        IF v_all_legal_moves.COUNT = 0 THEN
            UPDATE games SET status = CASE v_player_color WHEN 'W' THEN 'BLACK_WIN' ELSE 'WHITE_WIN' END, end_time = SYSTIMESTAMP,
                             winner_player_id = CASE v_player_color WHEN 'W' THEN v_game.player_black_id ELSE v_game.player_white_id END
            WHERE game_id = p_game_id;
            p_status_message := 'Ходов нет. Вы проиграли!'; COMMIT; RETURN;
        END IF;

        FOR i IN 1..v_all_legal_moves.COUNT LOOP
            DECLARE
                v_legal_move r_move := v_all_legal_moves(i);
                v_notation   VARCHAR2(50);
            BEGIN
                v_notation := idx_to_notation(v_legal_move.path(1).start_idx);
                FOR j IN 1..v_legal_move.path.COUNT LOOP
                    v_notation := v_notation || CASE v_legal_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END || idx_to_notation(v_legal_move.path(j).end_idx);
                END LOOP;
                v_legal_move.notation := v_notation;
                IF REPLACE(LOWER(p_move_notation), 'x', ':') = v_notation THEN
                    v_chosen_move := v_legal_move; v_is_move_valid := 'Y'; EXIT; -- --- ИЗМЕНЕНО ---
                END IF;
            END;
        END LOOP;

        IF v_is_move_valid = 'N' THEN -- --- ИЗМЕНЕНО ---
            IF v_all_legal_moves(1).is_capture = 'Y' THEN -- --- ИЗМЕНЕНО ---
                RAISE_APPLICATION_ERROR(-20007, 'Нелегальный ход. Взятие обязательно! Например: ' ||
                    idx_to_notation(v_all_legal_moves(1).path(1).start_idx) || ':' || idx_to_notation(v_all_legal_moves(1).path(1).end_idx));
            ELSE RAISE e_illegal_move; END IF;
        END IF;

        v_new_board := v_game.board_position;
        DECLARE
            v_moving_piece CHAR(1);
            v_start_pos PLS_INTEGER := v_chosen_move.path(1).start_idx;
            v_end_pos   PLS_INTEGER := v_chosen_move.path(v_chosen_move.path.LAST).end_idx;
        BEGIN
            v_moving_piece := SUBSTR(v_new_board, v_start_pos, 1);
            v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);
            IF v_chosen_move.is_capture = 'Y' THEN -- --- ИЗМЕНЕНО ---
                FOR i IN 1..v_chosen_move.path.COUNT LOOP
                    DECLARE v_captured_idx PLS_INTEGER := v_chosen_move.path(i).captured_idx;
                    BEGIN v_new_board := SUBSTR(v_new_board, 1, v_captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, v_captured_idx + 1); END;
                END LOOP;
            END IF;
            DECLARE v_end_row PLS_INTEGER := g_board_map(idx_to_notation(v_end_pos)).row_num;
            BEGIN
                IF v_moving_piece = c_white_man AND v_end_row = 8 THEN v_moving_piece := c_white_king;
                ELSIF v_moving_piece = c_black_man AND v_end_row = 1 THEN v_moving_piece := c_black_king; END IF;
            END;
            v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
        END;

        UPDATE games SET
            board_position = v_new_board, current_turn = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            last_move_at = SYSTIMESTAMP, moves_since_capture = CASE v_chosen_move.is_capture WHEN 'Y' THEN 0 ELSE v_game.moves_since_capture + 1 END
        WHERE game_id = p_game_id;

        SELECT COUNT(*) + 1 INTO v_move_count FROM game_moves WHERE game_id = p_game_id;
        INSERT INTO game_moves (game_id, move_number, player_id, move_notation, is_capture)
        VALUES (p_game_id, v_move_count, v_player_id, p_move_notation, v_chosen_move.is_capture); -- --- ИЗМЕНЕНО ---

        p_status_message := 'Ход ' || p_move_notation || ' принят.';
        COMMIT;
    EXCEPTION
        WHEN e_game_not_found OR e_game_is_over OR e_access_denied OR e_not_your_turn OR e_invalid_move_notation OR e_illegal_move THEN ROLLBACK; RAISE;
        WHEN OTHERS THEN
            ROLLBACK; v_error_details := SQLERRM;
            DECLARE v_err_player_id players.player_id%TYPE;
            BEGIN
                v_err_player_id := get_or_create_player_id(USER);
                INSERT INTO audit_log (player_id, game_id, event_type, event_details)
                VALUES (v_err_player_id, p_game_id, 'MAKE_MOVE_ERROR', v_error_details);
            END;
            COMMIT; RAISE;
    END make_move;
    
    PROCEDURE resign_game(p_game_id IN NUMBER) IS BEGIN RAISE_APPLICATION_ERROR(-20101, 'Функционал resign_game еще не реализован.'); END resign_game;
    FUNCTION get_game_status(p_game_id IN NUMBER) RETURN rec_game_status IS v_status rec_game_status; BEGIN RAISE_APPLICATION_ERROR(-20101, 'Функционал get_game_status еще не реализован.'); RETURN v_status; END get_game_status;

    FUNCTION get_printable_board(p_game_id IN NUMBER) RETURN CLOB IS
        -- Существующие переменные
        v_board_position  games.board_position%TYPE;
        v_clob            CLOB;
        v_char            CHAR(1);
        v_linear_idx      PLS_INTEGER;
        c_nl              CONSTANT VARCHAR2(1) := CHR(10);
        
        -- Переменные для данных об игре
        v_status          games.status%TYPE;
        v_current_turn    games.current_turn%TYPE;
        v_player_username players.username%TYPE; -- Новая переменная для имени игрока

    BEGIN
        BEGIN
            -- Усложняем запрос: получаем имя текущего игрока с помощью JOIN и CASE
            SELECT
                g.board_position,
                g.status,
                g.current_turn,
                p.username
            INTO
                v_board_position,
                v_status,
                v_current_turn,
                v_player_username
            FROM
                games g
            LEFT JOIN players p ON p.player_id = (
                CASE g.current_turn
                    WHEN 'W' THEN g.player_white_id
                    WHEN 'B' THEN g.player_black_id
                END
            )
            WHERE g.game_id = p_game_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE e_game_not_found;
        END;

        DBMS_LOB.createtemporary(v_clob, TRUE);

        IF v_status = 'ACTIVE' THEN
            -- Формируем строку с именем игрока и цветом его фигур
            DBMS_LOB.append(v_clob, 'Сейчас ходит ' || v_player_username || ' (' || v_current_turn || ')' || c_nl || c_nl);
        ELSE
            DBMS_LOB.append(v_clob, 'Состояние доски: ' || c_nl || c_nl);
        END IF;

        DBMS_LOB.append(v_clob, '  |  A   B   C   D   E   F   G   H  |' || c_nl);
        DBMS_LOB.append(v_clob, '--+---------------------------------+--' || c_nl);
        FOR i IN REVERSE 1..8 LOOP
            DBMS_LOB.append(v_clob, i || ' | ');
            FOR j IN 1..8 LOOP
                IF MOD(i + j, 2) != 0 THEN
                    v_linear_idx := ((8 - i) * 4) + CEIL(j / 2);
                    v_char := SUBSTR(v_board_position, v_linear_idx, 1);
                    IF v_char = c_empty_field THEN
                        DBMS_LOB.append(v_clob, '[ ] ');
                    ELSE
                        DBMS_LOB.append(v_clob, '[' || v_char || '] ');
                    END IF;
                ELSE
                    DBMS_LOB.append(v_clob, '    ');
                END IF;
            END LOOP;
            DBMS_LOB.append(v_clob, '| ' || i);
            DBMS_LOB.append(v_clob, c_nl);
        END LOOP;
        DBMS_LOB.append(v_clob, '--+---------------------------------+--' || c_nl);
        DBMS_LOB.append(v_clob, '  |  A   B   C   D   E   F   G   H  |' || c_nl);
        
        RETURN v_clob;
        
    END get_printable_board;

    FUNCTION get_possible_moves(p_game_id IN NUMBER) RETURN SYS_REFCURSOR IS BEGIN RAISE_APPLICATION_ERROR(-20101, 'Функционал get_possible_moves еще не реализован.'); RETURN NULL; END get_possible_moves;
    FUNCTION cleanup_stale_games(p_timeout_minutes IN NUMBER) RETURN NUMBER IS BEGIN RETURN 0; END cleanup_stale_games;

    FUNCTION get_my_active_game RETURN NUMBER IS
        v_game_id   games.game_id%TYPE;
        v_player_id players.player_id%TYPE;
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        SELECT g.game_id INTO v_game_id
        FROM games g WHERE g.status = 'ACTIVE'
          AND (g.player_white_id = v_player_id OR g.player_black_id = v_player_id) AND ROWNUM = 1;
        RETURN v_game_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
    END get_my_active_game;

    BEGIN -- Блок инициализации пакета
        FOR r IN 1..8 LOOP FOR c IN 1..8 LOOP
            IF MOD(r + c, 2) != 0 THEN
                DECLARE v_idx PLS_INTEGER := ((8 - r) * 4) + CEIL(c / 2); v_notation VARCHAR2(2) := CHR(ASCII('a') + c - 1) || r;
                BEGIN g_board_map(v_notation).idx := v_idx; g_board_map(v_notation).notation := v_notation; g_board_map(v_notation).row_num := r; g_board_map(v_notation).col_num := c; END;
            END IF;
        END LOOP; END LOOP;
END game_logic;
/