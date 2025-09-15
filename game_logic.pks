-- =============================================================================
-- Файл: game_logic.pks
-- Описание: Спецификация пакета game_logic.
--           Определяет публичный API для управления игровым процессом в шашки.
-- =============================================================================

CREATE OR REPLACE PACKAGE game_logic AS

    -- =========================================================================
    -- == ПУБЛИЧНЫЕ КОНСТАНТЫ И ТИПЫ
    -- =========================================================================

    -- Константы для представления фигур на доске. Используются для читаемости кода.
    c_white_man   CONSTANT VARCHAR2(1) := 'w';
    c_black_man   CONSTANT VARCHAR2(1) := 'b';
    c_white_king  CONSTANT VARCHAR2(1) := 'W';
    c_black_king  CONSTANT VARCHAR2(1) := 'B';
    c_empty_field CONSTANT VARCHAR2(1) := '_';

    -- Пользовательский тип-запись для возврата полной информации о состоянии игры
    -- одним объектом, чтобы избежать множества OUT-параметров.
    TYPE rec_game_status IS RECORD (
        game_id           games.game_id%TYPE,
        rule_name         game_rules.rule_name%TYPE,
        status            games.status%TYPE,
        current_turn      games.current_turn%TYPE,
        player_white      players.username%TYPE,
        player_black      players.username%TYPE,
        board_position    games.board_position%TYPE,
        last_move_at      games.last_move_at%TYPE,
        moves_since_capture games.moves_since_capture%TYPE,
        winner            players.username%TYPE
    );

    -- =========================================================================
    -- == ПУБЛИЧНЫЕ ИСКЛЮЧЕНИЯ
    -- =========================================================================
    -- Определяем именованные исключения для предсказуемой обработки ошибок на стороне клиента.

    e_player_is_busy        EXCEPTION; -- Игрок уже участвует в активной партии.
    e_invalid_opponent      EXCEPTION; -- Указанный оппонент не существует или некорректен.
    e_game_not_found        EXCEPTION; -- Партия с указанным ID не найдена или неактивна.
    e_not_your_turn         EXCEPTION; -- Попытка сделать ход не в свою очередь.
    e_game_is_over          EXCEPTION; -- Попытка сделать ход в уже завершенной партии.
    e_invalid_move_notation EXCEPTION; -- Нотация хода не соответствует формату (e.g., "a1-b2", "c3:e5").
    e_illegal_move          EXCEPTION; -- Ход нарушает правила игры (неверная траектория, тихий ход при обязательном взятии и т.д.).
    e_access_denied         EXCEPTION; -- Попытка выполнить действие в чужой партии.

    PRAGMA EXCEPTION_INIT(e_player_is_busy, -20001);
    PRAGMA EXCEPTION_INIT(e_invalid_opponent, -20002);
    PRAGMA EXCEPTION_INIT(e_game_not_found, -20003);
    PRAGMA EXCEPTION_INIT(e_not_your_turn, -20004);
    PRAGMA EXCEPTION_INIT(e_game_is_over, -20005);
    PRAGMA EXCEPTION_INIT(e_invalid_move_notation, -20006);
    PRAGMA EXCEPTION_INIT(e_illegal_move, -20007);
    PRAGMA EXCEPTION_INIT(e_access_denied, -20008);


    -- =========================================================================
    -- == ОСНОВНЫЕ ИГРОВЫЕ ПРОЦЕДУРЫ
    -- =========================================================================

    /**
     * Создает новую игровую партию.
     * Текущий пользователь Oracle (USER) становится одним из игроков.
     * @param p_opponent_username   Имя второго игрока (пользователя Oracle).
     * @param p_player_color        Цвет фигур для текущего пользователя ('W' или 'B'). Если NULL, цвет определяется случайно.
     * @param p_rule_id             ID правил из таблицы game_rules (по умолчанию 1 - русские шашки).
     * @param p_time_limit_move_sec Лимит времени на ход в секундах (необязательно).
     * @param p_time_limit_game_sec Лимит времени на партию в секундах (необязательно).
     * @param p_game_id             OUT: ID созданной партии.
     * @raises e_player_is_busy     Если текущий игрок или оппонент уже в игре.
     * @raises e_invalid_opponent   Если оппонент не найден или совпадает с текущим игроком.
     */
    PROCEDURE create_game(
        p_opponent_username   IN  VARCHAR2,
        p_player_color        IN  CHAR     DEFAULT NULL,
        p_rule_id             IN  NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN  NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN  NUMBER   DEFAULT NULL,
        p_game_id             OUT NUMBER
    );

    /**
     * Выполняет ход в активной партии.
     * Процедура выполняет полную валидацию хода: очередь, правила, обязательное взятие и т.д.
     * @param p_game_id         ID партии, в которой делается ход.
     * @param p_move_notation   Строка с нотацией хода. Примеры: "c3-d4" (тихий ход), "a3:c5" (однократное взятие), "g1:e3:c5" (многократное взятие).
     * @param p_status_message  OUT: Текстовое сообщение о результате хода (e.g., "Ход принят.", "Шах и мат! Белые победили.").
     * @raises e_game_not_found, e_access_denied, e_game_is_over, e_not_your_turn, e_invalid_move_notation, e_illegal_move.
     */
    PROCEDURE make_move(
        p_game_id         IN  NUMBER,
        p_move_notation   IN  VARCHAR2,
        p_status_message  OUT VARCHAR2
    );

    /**
     * Принудительно завершает партию (сдача).
     * Только участник партии может ее завершить.
     * @param p_game_id ID партии для завершения.
     * @raises e_game_not_found, e_access_denied, e_game_is_over.
     */
    PROCEDURE resign_game(
        p_game_id IN NUMBER
    );


    -- =========================================================================
    -- == ФУНКЦИИ И ПРОЦЕДУРЫ ДЛЯ ПОЛУЧЕНИЯ ИНФОРМАЦИИ
    -- =========================================================================

    /**
     * Возвращает детальный статус указанной партии.
     * Это основная процедура для получения "снимка" состояния игры.
     * @param p_game_id ID запрашиваемой партии.
     * @return Запись типа rec_game_status с полной информацией.
     * @raises e_game_not_found
     */
    FUNCTION get_game_status(
        p_game_id IN NUMBER
    ) RETURN rec_game_status;


    /**
     * Возвращает текстовое представление доски в удобочитаемом формате (8x8).
     * Предназначено для вывода в консоль.
     * @param p_game_id ID партии.
     * @return Многострочный текст (CLOB), изображающий доску с фигурами и координатами.
     * @raises e_game_not_found
     */
    FUNCTION get_printable_board(
        p_game_id IN NUMBER
    ) RETURN CLOB;
    
    
    /**
     * Возвращает список всех возможных валидных ходов для текущего игрока в указанной партии.
     * Полезно для отладки и для реализации подсказок на стороне клиента.
     * @param p_game_id ID партии.
     * @return SYS_REFCURSOR со столбцом 'move_notation'.
     * @raises e_game_not_found, e_game_is_over
     */
    FUNCTION get_possible_moves(
      p_game_id IN NUMBER
    ) RETURN SYS_REFCURSOR;


    -- =========================================================================
    -- == АДМИНИСТРАТИВНЫЕ ПРОЦЕДУРЫ
    -- =========================================================================

    /**
     * Процедура для автоматического завершения "подвисших" партий.
     * Находит все активные партии, где последний ход был сделан раньше,
     * чем `p_timeout_minutes` минут назад, и завершает их по таймауту.
     * Предназначена для вызова через DBMS_SCHEDULER.
     * @param p_timeout_minutes Порог неактивности в минутах.
     * @return Количество завершенных партий.
     */
    FUNCTION cleanup_stale_games(
        p_timeout_minutes IN NUMBER
    ) RETURN NUMBER;

END game_logic;


PROMPT Package specification GAME_LOGIC has been created successfully.