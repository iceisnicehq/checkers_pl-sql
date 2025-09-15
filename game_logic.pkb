-- =============================================================================
-- Файл: game_logic.pkb
-- Описание: Тело пакета game_logic.
--           Версия 1: Реализована процедура создания партии (create_game).
--           Для остального API созданы заглушки для успешной компиляции.
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY game_logic AS

    -- =========================================================================
    -- == ПРИВАТНЫЕ ПРОЦЕДУРЫ И ФУНКЦИИ (НЕ ВИДНЫ ВНЕ ПАКЕТА)
    -- =========================================================================

    /**
     * Получает ID игрока по его имени пользователя Oracle.
     * Если игрок не найден в таблице players, создает новую запись.
     * Это гарантирует, что любой пользователь, начинающий игру, будет зарегистрирован.
     * @param p_username Имя пользователя Oracle.
     * @return ID игрока из таблицы players.
     */
    FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
        v_player_id players.player_id%TYPE;
    BEGIN
        -- Пытаемся найти существующего игрока
        BEGIN
            SELECT player_id INTO v_player_id
            FROM players
            WHERE username = p_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Если не найден, создаем новую запись
                INSERT INTO players (username)
                VALUES (p_username)
                RETURNING player_id INTO v_player_id;

                -- Логируем событие регистрации нового игрока
                INSERT INTO audit_log (username, event_type, event_details)
                VALUES (p_username, 'PLAYER_REGISTERED', 'New player created automatically.');
        END;
        RETURN v_player_id;
    END get_or_create_player_id;

    /**
     * Генерирует начальную позицию на доске в виде строки.
     * @param p_rule_id ID правил игры.
     * @return Строка, представляющая начальную расстановку фигур.
     */
    FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
        v_board_position games.board_position%TYPE;
        v_rule           game_rules%ROWTYPE;
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;

        -- Пока реализуем только для русских шашек 8x8 (32 игровых поля)
        IF v_rule.rule_name = 'Русские шашки 8x8' THEN
            -- 12 черных, 8 пустых полей в центре, 12 белых
            v_board_position := RPAD(c_black_man, 12, c_black_man) ||
                                RPAD(c_empty_field, 8, c_empty_field) ||
                                RPAD(c_white_man, 12, c_white_man);
        ELSE
            -- В будущем здесь будет логика для других правил
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
    BEGIN
        -- 1. Валидация входных данных
        IF v_current_username = UPPER(p_opponent_username) THEN
            RAISE e_invalid_opponent; -- Нельзя играть с самим собой
        END IF;

        -- 2. Получаем ID игроков (или создаем их, если они новые)
        v_current_player_id  := get_or_create_player_id(v_current_username);
        v_opponent_player_id := get_or_create_player_id(UPPER(p_opponent_username));

        -- 3. Проверяем, не заняты ли игроки в других активных партиях
        SELECT COUNT(*)
        INTO v_active_game_count
        FROM games
        WHERE status = 'ACTIVE'
          AND (player_white_id IN (v_current_player_id, v_opponent_player_id) OR
               player_black_id IN (v_current_player_id, v_opponent_player_id));

        IF v_active_game_count > 0 THEN
            RAISE e_player_is_busy;
        END IF;

        -- 4. Определяем, кто играет каким цветом
        IF p_player_color = 'W' THEN
            v_white_player_id := v_current_player_id;
            v_black_player_id := v_opponent_player_id;
        ELSIF p_player_color = 'B' THEN
            v_white_player_id := v_opponent_player_id;
            v_black_player_id := v_current_player_id;
        ELSE -- Случайный выбор цвета, если не задан
            IF dbms_random.value < 0.5 THEN
                v_white_player_id := v_current_player_id;
                v_black_player_id := v_opponent_player_id;
            ELSE
                v_white_player_id := v_opponent_player_id;
                v_black_player_id := v_current_player_id;
            END IF;
        END IF;

        -- 5. Генерируем начальную позицию
        v_initial_position := get_initial_position(p_rule_id);

        -- 6. Создаем запись о новой партии в таблице
        INSERT INTO games (
            rule_id,
            player_white_id,
            player_black_id,
            status,
            current_turn,
            board_position,
            time_limit_move_sec,
            time_limit_game_sec
        ) VALUES (
            p_rule_id,
            v_white_player_id,
            v_black_player_id,
            'ACTIVE',
            'W', -- Белые всегда начинают
            v_initial_position,
            p_time_limit_move_sec,
            p_time_limit_game_sec
        ) RETURNING game_id INTO p_game_id;

        -- 7. Логируем событие создания игры
        INSERT INTO audit_log (game_id, event_type, event_details)
        VALUES (p_game_id, 'GAME_CREATED', 'Game created between ' || v_current_username || ' and ' || p_opponent_username);

        COMMIT;

    EXCEPTION
        WHEN e_invalid_opponent THEN
            ROLLBACK;
            RAISE;
        WHEN e_player_is_busy THEN
            ROLLBACK;
            RAISE;
        WHEN OTHERS THEN
            ROLLBACK;
            -- Логируем непредвиденную ошибку
            INSERT INTO audit_log (username, event_type, event_details)
            VALUES (v_current_username, 'CREATE_GAME_ERROR', SQLERRM);
            COMMIT;
            RAISE; -- Передаем ошибку дальше
    END create_game;

    ---------------------------------------------------------------------------
    -- ЗАГЛУШКИ ДЛЯ ОСТАЛЬНЫХ ПРОЦЕДУР И ФУНКЦИЙ
    ---------------------------------------------------------------------------

    PROCEDURE make_move(
        p_game_id         IN  NUMBER,
        p_move_notation   IN  VARCHAR2,
        p_status_message  OUT VARCHAR2
    ) IS
    BEGIN
        -- TODO: Реализовать логику валидации и выполнения хода
        p_status_message := 'Функционал make_move еще не реализован.';
        RAISE_APPLICATION_ERROR(-20101, p_status_message);
    END make_move;


    PROCEDURE resign_game(
        p_game_id IN NUMBER
    ) IS
    BEGIN
        -- TODO: Реализовать логику сдачи партии
        RAISE_APPLICATION_ERROR(-20101, 'Функционал resign_game еще не реализован.');
    END resign_game;


    FUNCTION get_game_status(
        p_game_id IN NUMBER
    ) RETURN rec_game_status IS
        v_status rec_game_status;
    BEGIN
        -- TODO: Реализовать логику получения статуса партии
        RAISE_APPLICATION_ERROR(-20101, 'Функционал get_game_status еще не реализован.');
        RETURN v_status; -- Эта строка нужна для компиляции
    END get_game_status;


    FUNCTION get_printable_board(
        p_game_id IN NUMBER
    ) RETURN CLOB IS
    BEGIN
        -- TODO: Реализовать логику форматирования доски для вывода
        RAISE_APPLICATION_ERROR(-20101, 'Функционал get_printable_board еще не реализован.');
        RETURN NULL;
    END get_printable_board;


    FUNCTION get_possible_moves(
      p_game_id IN NUMBER
    ) RETURN SYS_REFCURSOR IS
    BEGIN
      -- TODO: Реализовать логику поиска возможных ходов
      RAISE_APPLICATION_ERROR(-20101, 'Функционал get_possible_moves еще не реализован.');
      RETURN NULL;
    END get_possible_moves;


    FUNCTION cleanup_stale_games(
        p_timeout_minutes IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        -- TODO: Реализовать логику очистки "подвисших" партий
        RETURN 0;
    END cleanup_stale_games;

END game_logic;
/

SPOOL OFF;

PROMPT Package body GAME_LOGIC has been created successfully.