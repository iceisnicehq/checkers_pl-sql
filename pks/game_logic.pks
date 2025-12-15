CREATE OR REPLACE PACKAGE game_logic AS

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

    PROCEDURE info(p_query IN VARCHAR2 DEFAULT NULL);

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

    PROCEDURE draw(p_action IN CHAR); 

    PROCEDURE create_match(
        p_opponent_username   IN VARCHAR2 DEFAULT NULL,
        p_games_to_win        IN NUMBER   DEFAULT 3,
        p_player_color        IN CHAR     DEFAULT NULL, 
        p_rule_id             IN NUMBER   DEFAULT 1,
        p_time_limit_move_sec IN NUMBER   DEFAULT NULL, 
        p_time_limit_game_sec IN NUMBER   DEFAULT NULL, 
        p_draw_moves_limit    IN NUMBER   DEFAULT NULL, 
        p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'   
    );

    PROCEDURE join_match(p_match_id IN NUMBER); 

    PROCEDURE create_puzzle(
        p_board_position   IN CLOB,
        p_turn_to_move     IN CHAR,
        p_moves_to_solve   IN NUMBER DEFAULT NULL,
        p_difficulty_level IN CHAR DEFAULT 'M',
        p_solution         IN VARCHAR2 DEFAULT NULL
    );
    
    PROCEDURE show_puzzles(
        p_difficulty IN CHAR DEFAULT NULL, 
        p_puzzle_id  IN NUMBER DEFAULT NULL,
        p_solution   IN CHAR DEFAULT 'N'
    ); 
    
    PROCEDURE show_my_puzzles(p_difficulty IN CHAR DEFAULT NULL); 
    
    PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER);
    
    PROCEDURE show_daily_puzzle; 
    
    PROCEDURE print_active_board(
        p_game_id       IN NUMBER   DEFAULT NULL,
        p_username      IN VARCHAR2 DEFAULT NULL,
        p_wait_for_turn IN CHAR     DEFAULT 'N'
        ); 

    PROCEDURE watch_game_replay(
        p_game_id       IN NUMBER,
        p_moves_to_show IN NUMBER DEFAULT 1,
        p_restart       IN CHAR   DEFAULT 'N'
    ); 

    PROCEDURE stop_spectating; 

END game_logic;