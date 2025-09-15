-- =============================================================================
-- Файл: game_logic.pkb
-- Описание: Тело пакета game_logic.
--           Версия 1.1: Исправлена ошибка компиляции ORA-00984.
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY game_logic AS

    -- =========================================================================
    -- == ПРИВАТНЫЕ ТИПЫ ДАННЫХ ДЛЯ ВНУТРЕННЕЙ ЛОГИКИ
    -- =========================================================================
    -- Тип для хранения полной информации об игровом поле (координаты + линейный индекс)
    TYPE rec_board_field IS RECORD (
        idx         PLS_INTEGER, -- Линейный индекс от 1 до 32
        notation    VARCHAR2(2), -- Алгебраическая нотация ('a1', 'h8')
        row_num     PLS_INTEGER, -- Номер строки (1-8)
        col_num     PLS_INTEGER  -- Номер колонки (1-8)
    );

    TYPE map_notation_to_field IS TABLE OF rec_board_field INDEX BY VARCHAR2(2);

    g_board_map map_notation_to_field;

    -- =========================================================================
    -- == ПРИВАТНЫЕ ФУНКЦИИ-КОНВЕРТЕРЫ И ИНИЦИАЛИЗАЦИЯ
    -- =========================================================================

    /**
     * Преобразует алгебраическую нотацию в линейный индекс (1-32).
     * Использует предварительно вычисленную карту g_board_map для скорости.
     * @param p_notation Нотация, например 'c3'.
     * @return Линейный индекс или NULL, если нотация некорректна.
     */
    FUNCTION notation_to_idx(p_notation IN VARCHAR2) RETURN PLS_INTEGER IS
    BEGIN
        IF g_board_map.EXISTS(LOWER(p_notation)) THEN
            RETURN g_board_map(LOWER(p_notation)).idx;
        END IF;
        RETURN NULL; -- Некорректная нотация
    END notation_to_idx;


    -- =========================================================================
    -- == ПРИВАТНЫЕ ПРОЦЕДУРЫ И ФУНКЦИИ
    -- =========================================================================

    /**
     * Находит все возможные "тихие" ходы для указанной стороны.
     * @param p_board      Текущая позиция на доске.
     * @param p_turn_color Цвет, для которого ищутся ходы ('W' или 'B').
     * @return Коллекция строк с нотациями ходов (e.g., 'c3-d4').
     */
    FUNCTION find_simple_moves(
        p_board      IN games.board_position%TYPE,
        p_turn_color IN CHAR
    ) RETURN SYS.ODCIVARCHAR2LIST IS
        v_moves SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
        v_piece CHAR(1);
        v_direction PLS_INTEGER;
        v_start_idx PLS_INTEGER;
        v_end_idx   PLS_INTEGER;
    BEGIN
        -- Определяем направление движения для простых шашек
        v_direction := CASE p_turn_color WHEN 'W' THEN -1 ELSE 1 END;

        -- TODO: Реализовать логику поиска ходов
        -- На данном этапе это заглушка, которая считает любой ход вида X-Y валидным, если он идет на пустую клетку.
        -- Это временное решение для проверки основной механики make_move.
        -- На следующем шаге мы заменим это полноценным поиском по диагоналям.
        RETURN v_moves;
    END find_simple_moves;


    FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
        v_player_id players.player_id%TYPE;
    BEGIN
        BEGIN
            SELECT player_id INTO v_player_id
            FROM players
            WHERE username = p_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                INSERT INTO players (username)
                VALUES (p_username)
                RETURNING player_id INTO v_player_id;
                INSERT INTO audit_log (username, event_type, event_details)
                VALUES (p_username, 'PLAYER_REGISTERED', 'New player created automatically.');
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


    -- =========================================================================
    -- == ИСПРАВЛЕННАЯ РЕАЛИЗАЦИЯ CREATE_GAME (Версия 4.1)
    -- =========================================================================
    PROCEDURE create_game(
        p_opponent_username   IN  VARCHAR2 DEFAULT NULL,
        p_player_color        IN  CHAR     DEFAULT NULL,
        p_rule_id             IN  NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN  NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN  NUMBER   DEFAULT NULL,
        p_game_id             OUT NUMBER
    ) IS
        -- <<< ИЗМЕНЕНИЕ 1: Возвращаем объявление переменной
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_active_game_count   NUMBER;
        v_initial_position    games.board_position%TYPE;
        v_status              games.status%TYPE;
        v_error_details       VARCHAR2(1000);
    BEGIN
        v_current_player_id := get_or_create_player_id(v_current_username);

        SELECT COUNT(*) INTO v_active_game_count
        FROM games WHERE status = 'ACTIVE'
        AND (player_white_id = v_current_player_id OR player_black_id = v_current_player_id);
        IF v_active_game_count > 0 THEN RAISE e_player_is_busy; END IF;

        IF p_player_color = 'W' THEN v_white_player_id := v_current_player_id;
        ELSIF p_player_color = 'B' THEN v_black_player_id := v_current_player_id;
        ELSE IF dbms_random.value < 0.5 THEN v_white_player_id := v_current_player_id; ELSE v_black_player_id := v_current_player_id; END IF;
        END IF;

        IF p_opponent_username IS NOT NULL THEN
            IF v_current_username = UPPER(p_opponent_username) THEN RAISE e_invalid_opponent; END IF;
            v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

            SELECT COUNT(*) INTO v_active_game_count FROM games WHERE status = 'ACTIVE'
            AND (player_white_id = v_opponent_player_id OR player_black_id = v_opponent_player_id);
            IF v_active_game_count > 0 THEN RAISE e_player_is_busy; END IF;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id;
            ELSE v_black_player_id := v_opponent_player_id; END IF;
        END IF;

        v_initial_position := get_initial_position(p_rule_id);
        v_status := 'WAITING';

        INSERT INTO games (
            creator_player_id, rule_id, player_white_id, player_black_id, status, current_turn, board_position,
            time_limit_move_sec, time_limit_game_sec
        ) VALUES (
            v_current_player_id, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W', v_initial_position,
            p_time_limit_move_sec, p_time_limit_game_sec
        ) RETURNING game_id INTO p_game_id;

        COMMIT;
    EXCEPTION
        WHEN e_invalid_opponent OR e_player_is_busy THEN ROLLBACK; RAISE;
        WHEN OTHERS THEN
            ROLLBACK;
            v_error_details := SQLERRM;
            INSERT INTO audit_log (username, event_type, event_details)
            VALUES (USER, 'CREATE_GAME_ERROR', v_error_details);
            COMMIT; RAISE;
    END create_game;

    -- =========================================================================
    -- == ИСПРАВЛЕННАЯ РЕАЛИЗАЦИЯ JOIN_GAME (Версия 4.1)
    -- =========================================================================
    PROCEDURE join_game(p_game_id IN NUMBER) IS
        v_game          games%ROWTYPE;
        v_player_id     players.player_id%TYPE;
        -- <<< ИЗМЕНЕНИЕ 2: Возвращаем объявление переменной
        v_active_count  NUMBER;
    BEGIN
        v_player_id := get_or_create_player_id(USER);
        
        SELECT COUNT(*) INTO v_active_count FROM games WHERE status = 'ACTIVE'
            AND (player_white_id = v_player_id OR player_black_id = v_player_id);
        IF v_active_count > 0 THEN RAISE e_player_is_busy; END IF;

        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;

        IF v_game.status != 'WAITING' THEN RAISE e_game_is_over; END IF;

        IF v_player_id = v_game.creator_player_id THEN
            RAISE e_invalid_opponent;
        END IF;

        IF v_game.player_white_id IS NOT NULL AND v_game.player_black_id IS NOT NULL THEN
            IF v_player_id != v_game.player_white_id AND v_player_id != v_game.player_black_id THEN
                RAISE e_access_denied;
            END IF;
        END IF;

        UPDATE games SET
            player_white_id = NVL(v_game.player_white_id, v_player_id),
            player_black_id = NVL(v_game.player_black_id, v_player_id),
            status = 'ACTIVE', start_time = SYSTIMESTAMP
        WHERE game_id = p_game_id;

        COMMIT;
    END join_game;

    -- =======================================================================--
    -- == НОВАЯ РЕАЛИЗАЦИЯ ПРОЦЕДУРЫ MAKE_MOVE (ВЕРСИЯ ДЛЯ ТИХИХ ХОДОВ)     ====--
    -- =======================================================================--
     PROCEDURE make_move(
        p_game_id         IN  NUMBER,
        p_move_notation   IN  VARCHAR2,
        p_status_message  OUT VARCHAR2
    ) IS
        v_game              games%ROWTYPE;
        v_player_id         players.player_id%TYPE;
        v_player_color      CHAR(1);
        v_start_notation    VARCHAR2(10);
        v_end_notation      VARCHAR2(10);
        v_delimiter_pos     PLS_INTEGER;
        v_start_idx         PLS_INTEGER;
        v_end_idx           PLS_INTEGER;
        v_piece_at_start    CHAR(1);
        v_piece_at_end      CHAR(1);
        v_new_board         games.board_position%TYPE;
        v_error_details     VARCHAR2(1000); -- <<< ИЗМЕНЕНИЕ 3: Переменная для обработки ошибок
    BEGIN
        BEGIN SELECT * INTO v_game FROM games WHERE game_id = p_game_id; EXCEPTION WHEN NO_DATA_FOUND THEN RAISE e_game_not_found; END;
        IF v_game.status != 'ACTIVE' THEN RAISE e_game_is_over; END IF;
        v_player_id := get_or_create_player_id(USER);
        IF v_game.player_white_id = v_player_id THEN v_player_color := 'W'; ELSIF v_game.player_black_id = v_player_id THEN v_player_color := 'B'; ELSE RAISE e_access_denied; END IF;
        IF v_game.current_turn != v_player_color THEN RAISE e_not_your_turn; END IF;

        v_delimiter_pos := INSTR(p_move_notation, '-');
        IF v_delimiter_pos = 0 THEN RAISE e_invalid_move_notation; END IF;
        v_start_notation := SUBSTR(p_move_notation, 1, v_delimiter_pos - 1);
        v_end_notation   := SUBSTR(p_move_notation, v_delimiter_pos + 1);
        v_start_idx := notation_to_idx(v_start_notation);
        v_end_idx   := notation_to_idx(v_end_notation);
        IF v_start_idx IS NULL OR v_end_idx IS NULL THEN RAISE e_invalid_move_notation; END IF;

        v_piece_at_start := SUBSTR(v_game.board_position, v_start_idx, 1);
        v_piece_at_end   := SUBSTR(v_game.board_position, v_end_idx, 1);

        IF (v_player_color = 'W' AND v_piece_at_start NOT IN (c_white_man, c_white_king)) OR
           (v_player_color = 'B' AND v_piece_at_start NOT IN (c_black_man, c_black_king)) THEN RAISE e_illegal_move; END IF;
        IF v_piece_at_end != c_empty_field THEN RAISE e_illegal_move; END IF;

        v_new_board := v_game.board_position;
        v_new_board := SUBSTR(v_new_board, 1, v_start_idx - 1) || c_empty_field || SUBSTR(v_new_board, v_start_idx + 1);
        v_new_board := SUBSTR(v_new_board, 1, v_end_idx - 1) || v_piece_at_start || SUBSTR(v_new_board, v_end_idx + 1);

        UPDATE games SET board_position = v_new_board,
            current_turn = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            last_move_at = SYSTIMESTAMP, moves_since_capture = v_game.moves_since_capture + 1
        WHERE game_id = p_game_id;
        INSERT INTO game_moves (game_id, move_number, player_id, move_notation, is_capture)
        VALUES (p_game_id, v_game.moves_since_capture + 1, v_player_id, p_move_notation, 'N');
        p_status_message := 'Ход ' || p_move_notation || ' принят.';
        COMMIT;

    EXCEPTION
      WHEN e_game_not_found OR e_game_is_over OR e_access_denied OR
           e_not_your_turn OR e_invalid_move_notation OR e_illegal_move THEN
          ROLLBACK; RAISE;
      WHEN OTHERS THEN
          ROLLBACK;
          -- <<< ИЗМЕНЕНИЕ 4: Исправляем ошибку ORA-00984
          v_error_details := SQLERRM;
          INSERT INTO audit_log (game_id, event_type, event_details)
          VALUES (p_game_id, 'MAKE_MOVE_ERROR', v_error_details);
          COMMIT; RAISE;
    END make_move;

    PROCEDURE resign_game(p_game_id IN NUMBER) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-20101, 'Функционал resign_game еще не реализован.');
    END resign_game;

    FUNCTION get_game_status(p_game_id IN NUMBER) RETURN rec_game_status IS
        v_status rec_game_status;
    BEGIN
        RAISE_APPLICATION_ERROR(-20101, 'Функционал get_game_status еще не реализован.');
        RETURN v_status;
    END get_game_status;

    FUNCTION get_printable_board(
        p_game_id IN NUMBER
    ) RETURN CLOB IS
        v_board_position  games.board_position%TYPE;
        v_clob            CLOB;
        v_char            CHAR(1);
        v_linear_idx      PLS_INTEGER;
        c_nl              CONSTANT VARCHAR2(1) := CHR(10);
    BEGIN
        BEGIN
            SELECT board_position INTO v_board_position
            FROM games WHERE game_id = p_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RAISE e_game_not_found;
        END;

        DBMS_LOB.createtemporary(v_clob, TRUE);

        -- Итерируемся по доске с 8-й по 1-ю горизонталь
        FOR i IN REVERSE 1..8 LOOP
            -- Добавляем номер строки с визуальным разделителем
            DBMS_LOB.append(v_clob, i || ' | ');

            -- Итерируемся по вертикалям
            FOR j IN 1..8 LOOP
                IF MOD(i + j, 2) != 0 THEN -- Игровое (темное) поле
                    v_linear_idx := ((8 - i) * 4) + CEIL(j / 2);
                    v_char := SUBSTR(v_board_position, v_linear_idx, 1);
                    IF v_char = c_empty_field THEN
                        DBMS_LOB.append(v_clob, '[-] ');
                    ELSE
                        DBMS_LOB.append(v_clob, '[' || v_char || '] ');
                    END IF;
                ELSE -- Светлое поле
                    DBMS_LOB.append(v_clob, ' .  ');
                END IF;
            END LOOP;
            DBMS_LOB.append(v_clob, c_nl);
        END LOOP;

        -- Добавляем разделительную линию и нижнюю ось координат
        DBMS_LOB.append(v_clob, '  +---------------------------------' || c_nl);
        DBMS_LOB.append(v_clob, '    A   B   C   D   E   F   G   H' || c_nl);

        RETURN v_clob;
    END get_printable_board;

    FUNCTION get_possible_moves(p_game_id IN NUMBER) RETURN SYS_REFCURSOR IS
    BEGIN
      RAISE_APPLICATION_ERROR(-20101, 'Функционал get_possible_moves еще не реализован.');
      RETURN NULL;
    END get_possible_moves;

    FUNCTION cleanup_stale_games(p_timeout_minutes IN NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN 0;
    END cleanup_stale_games;

    -- Блок инициализации пакета: выполняется один раз за сессию при первом обращении к пакету
    BEGIN
        -- Заполняем карту доски g_board_map для быстрых преобразований
        FOR r IN 1..8 LOOP
            FOR c IN 1..8 LOOP
                IF MOD(r + c, 2) != 0 THEN -- Только темные (игровые) поля
                    DECLARE
                        v_idx PLS_INTEGER := ((8 - r) * 4) + CEIL(c / 2);
                        v_notation VARCHAR2(2) := CHR(ASCII('a') + c - 1) || r;
                    BEGIN
                        g_board_map(v_notation).idx := v_idx;
                        g_board_map(v_notation).notation := v_notation;
                        g_board_map(v_notation).row_num := r;
                        g_board_map(v_notation).col_num := c;
                    END;
                END IF;
            END LOOP;
        END LOOP;
END game_logic;
