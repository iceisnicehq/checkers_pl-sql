-- Файл: game_logic.pks (Спецификация)

CREATE OR REPLACE PACKAGE game_logic AS

    -- ... (все типы и исключения остаются как есть) ...
    c_white_man     CONSTANT VARCHAR2(1) := 'w';
    c_black_man     CONSTANT VARCHAR2(1) := 'b';
    c_white_king    CONSTANT VARCHAR2(1) := 'W';
    c_black_king    CONSTANT VARCHAR2(1) := 'B';
    c_empty_field   CONSTANT VARCHAR2(1) := '+';

    TYPE rec_game_status IS RECORD (
        game_id             games.game_id%TYPE,
        rule_name           game_rules.rule_name%TYPE,
        status              games.status%TYPE,
        current_turn        games.current_turn%TYPE,
        player_white        players.username%TYPE,
        player_black        players.username%TYPE,
        board_position      games.board_position%TYPE,
        last_move_at        games.last_move_at%TYPE,
        moves_since_capture games.moves_since_capture%TYPE,
        winner              players.username%TYPE
    );

    TYPE rec_move_notation IS RECORD (
        move_notation VARCHAR2(100)
    );
    TYPE tbl_move_notation IS TABLE OF rec_move_notation;

    e_player_is_busy            EXCEPTION;
    e_invalid_opponent          EXCEPTION;
    e_game_not_found            EXCEPTION;
    e_not_your_turn             EXCEPTION;
    e_game_is_over              EXCEPTION;
    e_invalid_move_notation     EXCEPTION;
    e_illegal_move              EXCEPTION;
    e_access_denied             EXCEPTION;
    e_replay_session_not_started EXCEPTION;
    e_replay_finished           EXCEPTION;
    e_opponent_is_busy          EXCEPTION; 

    PRAGMA EXCEPTION_INIT(e_player_is_busy, -20001);
    PRAGMA EXCEPTION_INIT(e_invalid_opponent, -20002);
    PRAGMA EXCEPTION_INIT(e_game_not_found, -20003);
    PRAGMA EXCEPTION_INIT(e_not_your_turn, -20004);
    PRAGMA EXCEPTION_INIT(e_game_is_over, -20005);
    PRAGMA EXCEPTION_INIT(e_invalid_move_notation, -20006);
    PRAGMA EXCEPTION_INIT(e_illegal_move, -20007);
    PRAGMA EXCEPTION_INIT(e_access_denied, -20008);
    PRAGMA EXCEPTION_INIT(e_replay_session_not_started, -20009);
    PRAGMA EXCEPTION_INIT(e_replay_finished, -20012);
    PRAGMA EXCEPTION_INIT(e_opponent_is_busy, -20020);

    -- ========================= [ НАЧАЛО ИЗМЕНЕНИЙ ] =========================
    PROCEDURE create_game(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_player_color        IN CHAR     DEFAULT NULL,
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_ai_difficulty       IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL
    );
    -- ========================== [ КОНЕЦ ИЗМЕНЕНИЙ ] ==========================

    PROCEDURE make_move(
            p_move_notation  IN VARCHAR2
    );
    
    PROCEDURE print_board(
        p_game_id     IN NUMBER   DEFAULT NULL,
        p_username    IN VARCHAR2 DEFAULT NULL,
        p_hide_header IN BOOLEAN  DEFAULT FALSE
    );
    
    PROCEDURE resign_game;
    PROCEDURE join_game(p_game_id IN NUMBER);
    PROCEDURE start_replay_session(p_game_id IN NUMBER);
    PROCEDURE show_next_replay_move( p_game_id IN NUMBER, p_moves_to_show IN NUMBER DEFAULT 1 );
    

    FUNCTION get_game_status(p_game_id IN NUMBER) RETURN rec_game_status;
    FUNCTION get_possible_moves(p_game_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION cleanup_stale_games(p_timeout_minutes IN NUMBER) RETURN NUMBER;

END game_logic;
/