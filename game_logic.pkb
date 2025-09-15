-- =============================================================================
-- Файл: game_logic.pkb
-- Описание: Тело пакета game_logic.
--           Версия 1.1: Исправлена ошибка компиляции ORA-00984.
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY game_logic AS

    -- =========================================================================
    -- == ПРИВАТНЫЕ ПРОЦЕДУРЫ И ФУНКЦИИ
    -- =========================================================================

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
            v_board_position := RPAD(c_black_man, 12, c_black_man) ||
                                RPAD(c_empty_field, 8, c_empty_field) ||
                                RPAD(c_white_man, 12, c_white_man);
        ELSE
            RAISE_APPLICATION_ERROR(-20100, 'Правила игры с ID=' || p_rule_id || ' не поддерживаются.');
        END IF;

        RETURN v_board_position;
    END get_initial_position;


    -- =========================================================================
    -- == РЕАЛИЗАЦИЯ ПУБЛИЧНЫХ ПРОЦЕДУР И ФУНКЦИЙ
    -- =========================================================================

    PROCEDURE create_game(
        p_opponent_username   IN  VARCHAR2,
        p_player_color        IN  CHAR     DEFAULT NULL,
        p_rule_id             IN  NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN  NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN  NUMBER   DEFAULT NULL,
        p_game_id             OUT NUMBER
    ) IS
        v_current_username    players.username%TYPE := USER;
        v_current_player_id   players.player_id%TYPE;
        v_opponent_player_id  players.player_id%TYPE;
        v_white_player_id     players.player_id%TYPE;
        v_black_player_id     players.player_id%TYPE;
        v_active_game_count   NUMBER;
        v_initial_position    games.board_position%TYPE;
        v_error_details       VARCHAR2(1000); -- <<< ИЗМЕНЕНИЕ 1: Добавлена переменная для ошибки
    BEGIN
        IF v_current_username = UPPER(p_opponent_username) THEN
            RAISE e_invalid_opponent;
        END IF;

        v_current_player_id  := get_or_create_player_id(v_current_username);
        v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

        SELECT COUNT(*)
        INTO v_active_game_count
        FROM games
        WHERE status = 'ACTIVE'
          AND (player_white_id IN (v_current_player_id, v_opponent_player_id) OR
               player_black_id IN (v_current_player_id, v_opponent_player_id));

        IF v_active_game_count > 0 THEN
            RAISE e_player_is_busy;
        END IF;

        IF p_player_color = 'W' THEN
            v_white_player_id := v_current_player_id;
            v_black_player_id := v_opponent_player_id;
        ELSIF p_player_color = 'B' THEN
            v_white_player_id := v_opponent_player_id;
            v_black_player_id := v_current_player_id;
        ELSE
            IF dbms_random.value < 0.5 THEN
                v_white_player_id := v_current_player_id;
                v_black_player_id := v_opponent_player_id;
            ELSE
                v_white_player_id := v_opponent_player_id;
                v_black_player_id := v_current_player_id;
            END IF;
        END IF;

        v_initial_position := get_initial_position(p_rule_id);

        INSERT INTO games (
            rule_id, player_white_id, player_black_id, status,
            current_turn, board_position, time_limit_move_sec, time_limit_game_sec
        ) VALUES (
            p_rule_id, v_white_player_id, v_black_player_id, 'ACTIVE',
            'W', v_initial_position, p_time_limit_move_sec, p_time_limit_game_sec
        ) RETURNING game_id INTO p_game_id;

        INSERT INTO audit_log (game_id, event_type, event_details)
        VALUES (p_game_id, 'GAME_CREATED', 'Game created between ' || v_current_username || ' and ' || p_opponent_username);

        COMMIT;

    EXCEPTION
        WHEN e_invalid_opponent OR e_player_is_busy THEN
            ROLLBACK;
            RAISE;
        WHEN OTHERS THEN
            ROLLBACK;
            v_error_details := SQLERRM; -- <<< ИЗМЕНЕНИЕ 2: Сначала присваиваем значение переменной
            -- Логируем непредвиденную ошибку
            INSERT INTO audit_log (username, event_type, event_details)
            VALUES (v_current_username, 'CREATE_GAME_ERROR', v_error_details); -- <<< ИЗМЕНЕНИЕ 3: Используем переменную
            COMMIT;
            RAISE;
    END create_game;

    ---------------------------------------------------------------------------
    -- ЗАГЛУШКИ ДЛЯ ОСТАЛЬНЫХ ПРОЦЕДУР И ФУНКЦИЙ
    ---------------------------------------------------------------------------

    PROCEDURE make_move(p_game_id IN NUMBER, p_move_notation IN VARCHAR2, p_status_message OUT VARCHAR2) IS
    BEGIN
        p_status_message := 'Функционал make_move еще не реализован.';
        RAISE_APPLICATION_ERROR(-20101, p_status_message);
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
        -- Получаем строку с позицией из БД
        BEGIN
            SELECT board_position INTO v_board_position
            FROM games
            WHERE game_id = p_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE e_game_not_found;
        END;

        -- Инициализируем CLOB для сборки результата
        DBMS_LOB.createtemporary(v_clob, TRUE);

        -- Итерируемся по доске с 8-й по 1-ю горизонталь
        FOR i IN REVERSE 1..8 LOOP
            DBMS_LOB.append(v_clob, i || ' '); -- Номер строки слева

            -- Итерируемся по вертикалям с 'A' по 'H' (1..8)
            FOR j IN 1..8 LOOP
                -- Проверяем, является ли поле игровым (темным)
                IF MOD(i + j, 2) != 0 THEN
                    -- Это игровое поле, вычисляем его индекс в нашей строке (1..32)
                    v_linear_idx := ((8 - i) * 4) + CEIL(j / 2);
                    v_char := SUBSTR(v_board_position, v_linear_idx, 1);

                    IF v_char = c_empty_field THEN
                        DBMS_LOB.append(v_clob, '[-] ');
                    ELSE
                        DBMS_LOB.append(v_clob, '[' || v_char || '] ');
                    END IF;
                ELSE
                    -- Это светлое (неигровое) поле
                    DBMS_LOB.append(v_clob, ' .  ');
                END IF;
            END LOOP;

            DBMS_LOB.append(v_clob, c_nl); -- Перенос строки
        END LOOP;

        -- Добавляем нижнюю ось координат в новом формате
        DBMS_LOB.append(v_clob, '   A   B   C   D   E   F   G   H' || c_nl);

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

END game_logic;
