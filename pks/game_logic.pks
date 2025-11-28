CREATE OR REPLACE PACKAGE game_logic AS

    -- =========================================================================
    -- ТИПЫ
    -- =========================================================================
    TYPE rec_move_notation IS RECORD (
        move_notation VARCHAR2(100)
    );
    TYPE tbl_move_notation IS TABLE OF rec_move_notation;

    TYPE rec_puzzle_list_item IS RECORD (
        puzzle_id        puzzles.puzzle_id%TYPE,
        difficulty_level puzzles.difficulty_level%TYPE,
        moves_to_solve   puzzles.moves_to_solve%TYPE,
        creator_username players.username%TYPE,
        board_position   puzzles.board_position%TYPE,
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

    TYPE r_move_step IS RECORD(
        start_idx    PLS_INTEGER,
        end_idx      PLS_INTEGER,
        captured_idx PLS_INTEGER
    );
    TYPE t_move_path IS TABLE OF r_move_step;

    TYPE r_move IS RECORD(
        notation      VARCHAR2(50),
        path          t_move_path,
        is_capture    CHAR(1),
        capture_count PLS_INTEGER,
        score         PLS_INTEGER
    );
    TYPE t_move_list IS TABLE OF r_move;
    
    TYPE t_map_indices IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;

    TYPE r_minimax_result IS RECORD (
        score NUMBER,
        move  r_move
    );

    PROCEDURE info(p_proc_name IN VARCHAR2 DEFAULT NULL);

    -- =========================================================================
    -- 1. УПРАВЛЕНИЕ ИГРОЙ (PvP, PvE, Puzzles)
    -- =========================================================================
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
    );

    PROCEDURE join_game(p_game_id IN NUMBER);

    PROCEDURE make_move(p_move_notation IN VARCHAR2);

    PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N'); 

    PROCEDURE cancel_game;

    -- =========================================================================
    -- 2. УПРАВЛЕНИЕ НИЧЬЕЙ
    -- =========================================================================
    PROCEDURE draw(p_action IN CHAR); 

    -- =========================================================================
    -- 3. УПРАВЛЕНИЕ МАТЧАМИ
    -- =========================================================================
    PROCEDURE create_match(
        p_opponent_username   IN VARCHAR2,
        p_games_to_win        IN NUMBER,
        p_player_color        IN CHAR     DEFAULT NULL, 
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL, 
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL, 
        p_draw_moves_limit    IN NUMBER   DEFAULT NULL, 
        p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'   
    );

    PROCEDURE join_match(p_match_id IN NUMBER); 

    -- =========================================================================
    -- 4. РЕЖИМ ЗАДАЧ (Puzzles)
    -- =========================================================================
    PROCEDURE create_puzzle(
        p_board_position   IN CLOB,
        p_turn_to_move     IN CHAR,
        p_moves_to_solve   IN NUMBER DEFAULT NULL,
        p_difficulty_level IN CHAR DEFAULT 'E'
    );
    
    PROCEDURE show_puzzles(p_difficulty IN CHAR DEFAULT NULL, p_puzzle_id IN NUMBER DEFAULT NULL); 
    
    PROCEDURE show_my_puzzles(p_difficulty IN CHAR DEFAULT NULL); 
    
    PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER);
    
    PROCEDURE show_daily_puzzle; 
    
    -- =========================================================================
    -- 5. ПРОСМОТР И СТАТУС (Режим Зрителя и Реплеи)
    -- =========================================================================
    PROCEDURE print_active_board(
        p_game_id       IN NUMBER   DEFAULT NULL,
        p_username      IN VARCHAR2 DEFAULT NULL,
        p_wait_for_turn IN CHAR     DEFAULT 'N' -- <-- ИЗМЕНЕНИЕ: Добавлен флаг
    ); 

    PROCEDURE watch_game_replay( -- <-- ИЗМЕНЕНИЕ: Переименовано
        p_game_id       IN NUMBER,
        p_moves_to_show IN NUMBER DEFAULT 1
    ); 

    PROCEDURE stop_spectating; 

    -- =========================================================================
    -- 6. БЫВШИЕ "ПРИВАТНЫЕ" (ТЕПЕРЬ ПУБЛИЧНЫЕ) ФУНКЦИИ
    -- =========================================================================
    PROCEDURE p_init_board_map(
        p_board_size IN NUMBER
    );

    PROCEDURE p_audit_log(
        p_player_id  IN players.player_id%TYPE,
        p_game_id    IN games.game_id%TYPE,
        p_event_msg  IN audit_log.event_msg%TYPE 
    );

    PROCEDURE p_update_ratings(
        p_game_id IN games.game_id%TYPE
    );

    PROCEDURE p_process_move(
        p_game_id        IN NUMBER,
        p_move_notation  IN VARCHAR2,
        p_player_id      IN NUMBER, -- NULL для ИИ
        p_status_message OUT VARCHAR2
    );

    -- =========================================================================

    FUNCTION encode_board(
        p_decoded_board IN VARCHAR2
    ) RETURN VARCHAR2;

    FUNCTION decode_board(
        p_encoded_board IN VARCHAR2
    ) RETURN VARCHAR2;

    FUNCTION get_active_game(
        p_user_id IN players.player_id%TYPE
    ) RETURN NUMBER;

    FUNCTION get_or_create_player_id(
        p_username IN VARCHAR2
    ) RETURN NUMBER;

    FUNCTION get_initial_position(
        p_rule_id IN NUMBER
    ) RETURN VARCHAR2;
    
    FUNCTION f_get_board_as_clob(
        p_board_position  IN VARCHAR2,
        p_highlight_indices IN t_map_indices DEFAULT t_map_indices()
    ) RETURN CLOB;

    FUNCTION find_capture_paths(
        p_start_idx    IN PLS_INTEGER,
        p_board        IN VARCHAR2,
        p_player_color IN CHAR,
        p_is_king      IN CHAR,
        p_rule_id      IN NUMBER,
        p_visited_path IN t_move_path DEFAULT t_move_path()
    ) RETURN t_move_list;

    FUNCTION find_all_player_moves(
        p_board        IN VARCHAR2,
        p_player_color IN CHAR,
        p_rule_id      IN NUMBER
    ) RETURN t_move_list;

    FUNCTION apply_move_to_board(
        p_board IN VARCHAR2,
        p_move  IN r_move,
        p_color IN CHAR
    ) RETURN VARCHAR2;

    FUNCTION minimax(
        p_board         IN VARCHAR2,
        p_depth         IN PLS_INTEGER,
        p_alpha         IN NUMBER,
        p_beta          IN NUMBER,
        p_is_maximizing IN BOOLEAN,
        p_ai_color      IN CHAR,
        p_difficulty    IN CHAR,
        p_rule_id       IN NUMBER
    ) RETURN r_minimax_result;

    FUNCTION get_ai_move(
        p_board_position IN game_moves.board_position%TYPE,
        p_ai_color       IN games.current_turn%TYPE,
        p_rule_id        IN games.rule_id%TYPE,
        p_difficulty     IN games.ai_difficulty%TYPE
    ) RETURN VARCHAR2;

END game_logic;