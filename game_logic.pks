-- Файл: game_logic.pks (Спецификация)

CREATE OR REPLACE PACKAGE game_logic AS

    -- ... (все типы и исключения остаются как есть) ...
    c_white_man     CONSTANT VARCHAR2(1) := 'w';
    c_black_man     CONSTANT VARCHAR2(1) := 'b';
    c_white_king    CONSTANT VARCHAR2(1) := 'W';
    c_black_king    CONSTANT VARCHAR2(1) := 'B';
    c_empty_field   CONSTANT VARCHAR2(1) := '+';

    -- TYPE rec_game_status IS RECORD (
    --     game_id             games.game_id%TYPE,
    --     rule_name           game_rules.rule_name%TYPE,
    --     status              games.status%TYPE,
    --     current_turn        games.current_turn%TYPE,
    --     player_white        players.username%TYPE,
    --     player_black        players.username%TYPE,
    --     board_position      games.board_position%TYPE,
    --     last_move_at        games.last_move_at%TYPE,
    --     moves_since_capture games.moves_since_capture%TYPE,
    --     winner              players.username%TYPE
    -- );

    TYPE rec_move_notation IS RECORD (
        move_notation VARCHAR2(100)
    );
    TYPE tbl_move_notation IS TABLE OF rec_move_notation;

    TYPE rec_puzzle_list_item IS RECORD (
        puzzle_id        puzzles.puzzle_id%TYPE,
        -- rule_id and rule_name removed as they are derived client-side now
        difficulty_level puzzles.difficulty_level%TYPE,
        moves_to_solve   puzzles.moves_to_solve%TYPE,
        creator_username players.username%TYPE,
        board_position   puzzles.board_position%TYPE, -- Remains encoded
        turn_to_move     puzzles.turn_to_move%TYPE
    );

    TYPE tbl_puzzle_list IS TABLE OF rec_puzzle_list_item;

    TYPE rec_daily_puzzle_info IS RECORD (
        puzzle_date      daily_puzzles.puzzle_date%TYPE,
        puzzle_id        puzzles.puzzle_id%TYPE,
        difficulty_level puzzles.difficulty_level%TYPE,
        moves_to_solve   puzzles.moves_to_solve%TYPE,
        turn_to_move     puzzles.turn_to_move%TYPE,
        board_position   puzzles.board_position%TYPE
    );
    TYPE tbl_daily_puzzle_info IS TABLE OF rec_daily_puzzle_info;

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
    e_puzzle_not_found    EXCEPTION;
    e_no_active_puzzle    EXCEPTION;
    e_daily_puzzle_missing EXCEPTION;
    e_attempt_in_progress EXCEPTION;
    e_invalid_board_str   EXCEPTION;

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
    PRAGMA EXCEPTION_INIT(e_puzzle_not_found, -20032);
    PRAGMA EXCEPTION_INIT(e_no_active_puzzle, -20033);
    PRAGMA EXCEPTION_INIT(e_daily_puzzle_missing, -20030);
    PRAGMA EXCEPTION_INIT(e_attempt_in_progress, -20031);
    PRAGMA EXCEPTION_INIT(e_invalid_board_str, -20035);
    
    -- ========================= [ НАЧАЛО ИЗМЕНЕНИЙ ] =========================
    PROCEDURE create_game(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_player_color        IN CHAR DEFAULT NULL,
        p_rule_id             IN NUMBER DEFAULT 1,
        p_ai_difficulty       IN NUMBER DEFAULT NULL, -- << ENSURE THIS IS NULL
        p_time_limit_move_sec IN NUMBER DEFAULT NULL,
        p_time_limit_game_sec IN NUMBER DEFAULT NULL,
        p_start_position      IN VARCHAR2 DEFAULT NULL -- From puzzle logic
        -- p_game_type        IN VARCHAR2 DEFAULT 'STANDARD' -- Optional
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

    -- FUNCTION get_game_status(p_game_id IN NUMBER) RETURN rec_game_status;
    FUNCTION get_possible_moves(p_game_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION cleanup_stale_games(p_timeout_minutes IN NUMBER) RETURN NUMBER;

    -- NEW PROCEDURES & FUNCTIONS for Puzzles
    PROCEDURE start_puzzle(
        p_puzzle_id IN NUMBER,
        p_is_daily  IN CHAR DEFAULT 'N' -- << ADD THIS PARAMETER
    );
    PROCEDURE create_puzzle(
        p_board_position   IN VARCHAR2,
        p_turn_to_move     IN CHAR,
        p_moves_to_solve   IN NUMBER DEFAULT NULL, -- Keep as NOT NULL for now per your DDL
        p_difficulty_level IN NUMBER
    );
    PROCEDURE show_puzzles(
        p_difficulty     IN NUMBER DEFAULT NULL
    );
    PROCEDURE show_my_puzzles;
    PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER);
    PROCEDURE show_daily_puzzle(
        p_date_str IN VARCHAR2 DEFAULT NULL -- Format 'DD.MM.YYYY'
    );
    PROCEDURE start_daily_puzzle;
    PROCEDURE make_puzzle_move(p_move_notation IN VARCHAR2);
    PROCEDURE print_puzzle_board;
    PROCEDURE quit_puzzle_attempt;

END game_logic;
/