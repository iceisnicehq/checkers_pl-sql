CREATE OR REPLACE PACKAGE BODY game_logic AS

    c_white_man     CONSTANT VARCHAR2(1) := 'w';
    c_black_man     CONSTANT VARCHAR2(1) := 'b';
    c_white_king    CONSTANT VARCHAR2(1) := 'W';
    c_black_king    CONSTANT VARCHAR2(1) := 'B';
    c_empty_field   CONSTANT VARCHAR2(1) := '+';
    c_nl            CONSTANT VARCHAR2(1) := CHR(10);

    TYPE rec_board_field IS RECORD(
        idx      PLS_INTEGER,
        notation VARCHAR2(50),
        row_num  PLS_INTEGER,
        col_num  PLS_INTEGER
    );

    TYPE map_notation_to_field IS TABLE OF rec_board_field INDEX BY VARCHAR2(50);

    TYPE map_idx_to_field IS TABLE OF rec_board_field INDEX BY PLS_INTEGER;

    g_map_by_notation   map_notation_to_field;
    g_map_by_idx        map_idx_to_field;

    g_current_map_size  PLS_INTEGER := 0;

FUNCTION encode_board(p_decoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_encoded_board VARCHAR2(100) := '';
    v_plus_count    PLS_INTEGER := 0;
    v_char          CHAR(1);
BEGIN
    FOR i IN 1 .. LENGTH(p_decoded_board) LOOP
        v_char := SUBSTR(p_decoded_board, i, 1);
        IF v_char = c_empty_field THEN
            v_plus_count := v_plus_count + 1;
        ELSE
            IF v_plus_count > 0 THEN
                v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
                v_plus_count := 0;
            END IF;
            v_encoded_board := v_encoded_board || v_char;
        END IF;
    END LOOP;

    IF v_plus_count > 0 THEN
        v_encoded_board := v_encoded_board || TO_CHAR(v_plus_count);
    END IF;

    RETURN v_encoded_board;
END encode_board;

FUNCTION decode_board(p_encoded_board IN VARCHAR2) RETURN VARCHAR2 IS
    v_decoded_board VARCHAR2(100) := ''; 
    v_num_str       VARCHAR2(2) := '';
    v_char          CHAR(1);
    i               PLS_INTEGER := 1;
BEGIN
    WHILE i <= LENGTH(p_encoded_board) LOOP
        v_char := SUBSTR(p_encoded_board, i, 1);

        IF v_char BETWEEN '0' AND '9' THEN
            v_num_str := v_num_str || v_char;
        ELSE
            IF v_num_str IS NOT NULL THEN
                v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
                v_num_str := '';
            END IF;
            v_decoded_board := v_decoded_board || v_char;
        END IF;
        i := i + 1;
    END LOOP;

    IF v_num_str IS NOT NULL THEN
        v_decoded_board := v_decoded_board || RPAD(c_empty_field, TO_NUMBER(v_num_str), c_empty_field);
    END IF;

    RETURN v_decoded_board;
END decode_board;

FUNCTION get_active_game(p_user_id IN players.player_id%TYPE) RETURN NUMBER IS
    v_game_id games.game_id%TYPE;
BEGIN

    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM games
        WHERE (player_white_id = p_user_id OR player_black_id = p_user_id)
          AND (

              status IN ('A', 'O')
              OR

              (status = 'C' AND (
                  (creator_player_color = 'W' AND player_white_id = p_user_id) OR
                  (creator_player_color = 'B' AND player_black_id = p_user_id)
              ))
          );

        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
    END;

    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM spectators
        WHERE player_id = p_user_id
          AND left_at IS NULL;

        RETURN v_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            RETURN NULL;
    END;
END get_active_game;

FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
    v_player_id players.player_id%TYPE;
BEGIN
    BEGIN
        SELECT player_id
        INTO v_player_id
        FROM players
        WHERE username = p_username;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            INSERT INTO players (username)
            VALUES (p_username)
            RETURNING player_id INTO v_player_id;
    END;
    RETURN v_player_id;
END get_or_create_player_id;

PROCEDURE p_audit_log(
    p_player_id  IN players.player_id%TYPE,
    p_game_id    IN games.game_id%TYPE,
    p_event_msg  IN audit_log.event_msg%TYPE
) IS PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log (
        player_id, 
        game_id, 
        event_msg
    )
    VALUES (
        p_player_id, 
        p_game_id, 
        SUBSTR(p_event_msg, 1, 2000)
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN NULL;
END p_audit_log;


FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
    v_rule      game_rules%ROWTYPE;
    v_error_msg VARCHAR2(2000); 
BEGIN

    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
            p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN NULL;
    END;

    IF v_rule.board_size = 8 THEN
        RETURN '+b+b+b+b' ||
               'b+b+b+b+' ||
               '+b+b+b+b' ||
               '++++++++' ||
               '++++++++' ||
               'w+w+w+w+' ||
               '+w+w+w+w' ||
               'w+w+w+w+';
    ELSE
        RETURN '+b+b+b+b+b' ||
               'b+b+b+b+b+' ||
               '+b+b+b+b+b' ||
               'b+b+b+b+b+' ||
               '++++++++++' ||
               '++++++++++' ||
               '+w+w+w+w+w' ||
               'w+w+w+w+w+' ||
               '+w+w+w+w+w' ||
               'w+w+w+w+w+';
    END IF;
END get_initial_position;

FUNCTION f_is_valid_index(
    p_idx           IN PLS_INTEGER,
    p_total_squares IN PLS_INTEGER,
    p_start_col     IN PLS_INTEGER,
    p_expected_col_diff IN PLS_INTEGER
) RETURN BOOLEAN IS
BEGIN
    RETURN p_idx BETWEEN 1 AND p_total_squares
       AND g_map_by_idx.EXISTS(p_idx)
       AND ABS(p_start_col - g_map_by_idx(p_idx).col_num) = p_expected_col_diff;
END f_is_valid_index;

PROCEDURE p_init_board_map(p_board_size IN NUMBER) IS
    v_idx       PLS_INTEGER;
    v_notation  VARCHAR2(50);
    v_field_rec rec_board_field;
BEGIN

    IF p_board_size = g_current_map_size THEN
        RETURN;
    END IF;

    g_map_by_notation.DELETE;
    g_map_by_idx.DELETE;

    FOR r IN 1 .. p_board_size LOOP
        FOR c IN 1 .. p_board_size LOOP

            v_idx := ((p_board_size - r) * p_board_size) + c;

            v_notation := CHR(ASCII('a') + c - 1) || r;

            v_field_rec.idx      := v_idx;
            v_field_rec.notation := v_notation;
            v_field_rec.row_num  := r;
            v_field_rec.col_num  := c;

            g_map_by_notation(v_notation) := v_field_rec;
            g_map_by_idx(v_idx)           := v_field_rec;
            
        END LOOP;
    END LOOP;

    g_current_map_size := p_board_size;
    
END p_init_board_map;

FUNCTION f_move_to_notation(
    p_move      IN r_move,
    p_board_size IN PLS_INTEGER
) RETURN VARCHAR2 IS
    v_notation VARCHAR2(100);
BEGIN
    IF p_move.path IS NULL OR p_move.path.COUNT = 0 THEN
        RETURN NULL;
    END IF;

    p_init_board_map(p_board_size);

    v_notation := g_map_by_idx(p_move.path(1).start_idx).notation;

    FOR j IN 1 .. p_move.path.COUNT LOOP
        v_notation := v_notation || CASE p_move.is_capture WHEN 'Y' THEN ':' ELSE '-' END 
                      || g_map_by_idx(p_move.path(j).end_idx).notation;
    END LOOP;
    
    RETURN v_notation;
END f_move_to_notation;

FUNCTION find_capture_paths(
    p_start_idx    IN PLS_INTEGER,
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_is_king      IN CHAR,
    p_rule_id      IN NUMBER,
    p_visited_path IN t_move_path DEFAULT t_move_path()
) RETURN t_move_list IS
    v_results             t_move_list := t_move_list();
    v_leaf_paths          t_move_list := t_move_list();
    v_opponent_man        CHAR(1);
    v_opponent_king       CHAR(1);
    v_decoded_board       VARCHAR2(100) := decode_board(p_board);
    
    v_rule                game_rules%ROWTYPE;
    v_board_size          PLS_INTEGER;
    v_total_squares       PLS_INTEGER;
    v_player_promotion_row PLS_INTEGER;
    v_max_king_range      PLS_INTEGER;
    v_jump_directions     SYS.ODCINUMBERLIST;
    v_start_field         rec_board_field;
    
BEGIN

    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;

        v_player_promotion_row := CASE p_player_color WHEN 'W' THEN v_board_size ELSE 1 END;
        v_max_king_range  := v_board_size - 1; 

        p_init_board_map(v_board_size);
        
        v_start_field := g_map_by_idx(p_start_idx);

        IF v_board_size = 8 THEN
            v_jump_directions := SYS.ODCINUMBERLIST(-18, -14, 14, 18);
        ELSE
            v_jump_directions := SYS.ODCINUMBERLIST(-22, -18, 18, 22);
        END IF;
    END;

    IF p_player_color = 'W' THEN
        v_opponent_man  := c_black_man;
        v_opponent_king := c_black_king;
    ELSE
        v_opponent_man  := c_white_man;
        v_opponent_king := c_white_king;
    END IF;

    FOR i IN 1 .. v_jump_directions.COUNT LOOP
        DECLARE
            v_jump        PLS_INTEGER := v_jump_directions(i);
            v_land_idx    PLS_INTEGER;
            v_capture_idx PLS_INTEGER;
            v_is_visited  BOOLEAN := FALSE;
        BEGIN

            IF p_is_king = 'N' THEN
                v_land_idx    := p_start_idx + v_jump;
                v_capture_idx := p_start_idx + (v_jump / 2);

                IF f_is_valid_index(v_land_idx, v_total_squares, v_start_field.col_num, 2) THEN

                    IF SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field 
                       AND SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) 
                    THEN

                        FOR kk IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(kk).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;

                        IF NOT v_is_visited THEN
                            DECLARE
                                v_becomes_king        CHAR(1) := 'N';
                                v_land_row            PLS_INTEGER := g_map_by_idx(v_land_idx).row_num; 
                                v_is_promotion_square BOOLEAN := (v_land_row = v_player_promotion_row);
                                v_step                r_move_step;
                                v_new_path            t_move_path := p_visited_path;
                                v_sub_paths           t_move_list;
                                v_move                r_move;
                            BEGIN
                                v_step.start_idx    := p_start_idx;
                                v_step.end_idx      := v_land_idx;
                                v_step.captured_idx := v_capture_idx;
                                v_new_path.EXTEND;
                                v_new_path(v_new_path.LAST) := v_step;

                                IF p_rule_id = 1 AND v_is_promotion_square THEN
                                    v_becomes_king := 'Y';
                                END IF;

                                v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, v_becomes_king, p_rule_id, v_new_path);

                                IF v_sub_paths.COUNT = 0 THEN

                                    v_move.path          := v_new_path;
                                    v_move.is_capture    := 'Y';
                                    v_move.capture_count := v_new_path.COUNT;
                                    v_leaf_paths.EXTEND;
                                    v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                ELSE

                                    FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                        v_results.EXTEND;
                                        v_results(v_results.LAST) := v_sub_paths(j);
                                    END LOOP;
                                END IF;
                            END;
                        END IF;
                    END IF;
                END IF;

            ELSE 
                FOR k IN 1 .. v_max_king_range LOOP 
                    v_capture_idx := p_start_idx + (v_jump / 2 * k);

                    IF NOT f_is_valid_index(v_capture_idx, v_total_squares, v_start_field.col_num, k) THEN
                        EXIT;
                    END IF;

                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) IN (v_opponent_man, v_opponent_king) THEN

                        FOR m IN 1 .. p_visited_path.COUNT LOOP
                            IF p_visited_path(m).captured_idx = v_capture_idx THEN
                                v_is_visited := TRUE;
                                EXIT;
                            END IF;
                        END LOOP;
                        IF v_is_visited THEN EXIT; END IF;

                        DECLARE
                            v_capture_field rec_board_field := g_map_by_idx(v_capture_idx);
                        BEGIN
                            FOR l IN (k + 1) .. v_board_size LOOP 

                                v_land_idx := v_capture_idx + (v_jump / 2 * (l - k));

                                IF NOT f_is_valid_index(v_land_idx, v_total_squares, v_capture_field.col_num, (l - k)) THEN
                                    EXIT;
                                END IF;

                                DECLARE
                                    v_path_is_clear BOOLEAN := TRUE;
                                    v_check_idx     PLS_INTEGER;
                                BEGIN

                                    FOR check_pos IN (k + 1) .. (l - 1) LOOP
                                        v_check_idx := p_start_idx + (v_jump / 2 * check_pos);
                                        IF f_is_valid_index(v_check_idx, v_total_squares, v_start_field.col_num, check_pos) THEN
                                            IF SUBSTR(v_decoded_board, v_check_idx, 1) != c_empty_field THEN
                                                v_path_is_clear := FALSE;
                                                EXIT;
                                            END IF;
                                        END IF;
                                    END LOOP;

                                    IF v_path_is_clear AND SUBSTR(v_decoded_board, v_land_idx, 1) = c_empty_field THEN
                                        DECLARE
                                            v_step      r_move_step;
                                            v_new_path  t_move_path := p_visited_path;
                                            v_sub_paths t_move_list;
                                            v_move      r_move;
                                        BEGIN
                                            v_step.start_idx    := p_start_idx;
                                            v_step.end_idx      := v_land_idx;
                                            v_step.captured_idx := v_capture_idx;
                                            v_new_path.EXTEND;
                                            v_new_path(v_new_path.LAST) := v_step;

                                            v_sub_paths := find_capture_paths(v_land_idx, v_decoded_board, p_player_color, 'Y', p_rule_id, v_new_path);

                                            IF v_sub_paths.COUNT = 0 THEN
                                                v_move.path          := v_new_path;
                                                v_move.is_capture    := 'Y';
                                                v_move.capture_count := v_new_path.COUNT;
                                                v_leaf_paths.EXTEND;
                                                v_leaf_paths(v_leaf_paths.LAST) := v_move;
                                            ELSE
                                                FOR j IN 1 .. v_sub_paths.COUNT LOOP
                                                    v_results.EXTEND;
                                                    v_results(v_results.LAST) := v_sub_paths(j);
                                                END LOOP;
                                            END IF;
                                        END;
                                    ELSIF NOT v_path_is_clear OR SUBSTR(v_decoded_board, v_land_idx, 1) != c_empty_field THEN

                                        EXIT;
                                    END IF;
                                END;
                            END LOOP;
                        END;
                        EXIT;
                    END IF;

                    IF SUBSTR(v_decoded_board, v_capture_idx, 1) != c_empty_field THEN
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END;
    END LOOP;
    
    IF v_results.COUNT > 0 THEN
        RETURN v_results;
    ELSE
        RETURN v_leaf_paths;
    END IF;

END find_capture_paths;

FUNCTION find_all_player_moves(
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_rule_id      IN NUMBER
) RETURN t_move_list IS
    v_all_moves       t_move_list := t_move_list();
    v_capture_moves   t_move_list := t_move_list();
    v_simple_moves    t_move_list := t_move_list();
    v_player_man      CHAR(1);
    v_player_king     CHAR(1);
    v_max_captures    PLS_INTEGER := 0;
    v_decoded_board   VARCHAR2(100) := decode_board(p_board);
    
    v_rule            game_rules%ROWTYPE;
    v_board_size      PLS_INTEGER;
    v_total_squares   PLS_INTEGER;
    v_simple_move_w   SYS.ODCINUMBERLIST;
    v_simple_move_b   SYS.ODCINUMBERLIST;
    v_simple_move_all SYS.ODCINUMBERLIST;
    v_max_king_range  PLS_INTEGER;
    v_simple_directions SYS.ODCINUMBERLIST;

BEGIN

    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_max_king_range  := v_board_size - 1;
        
        p_init_board_map(v_board_size);
        
        IF v_board_size = 8 THEN
            v_simple_move_w   := SYS.ODCINUMBERLIST(-9, -7);
            v_simple_move_b   := SYS.ODCINUMBERLIST(7, 9);
            v_simple_move_all := SYS.ODCINUMBERLIST(-9, -7, 7, 9);
        ELSE
            v_simple_move_w   := SYS.ODCINUMBERLIST(-11, -9);
            v_simple_move_b   := SYS.ODCINUMBERLIST(9, 11);
            v_simple_move_all := SYS.ODCINUMBERLIST(-11, -9, 9, 11);
        END IF;
    END;

    IF p_player_color = 'W' THEN
        v_player_man  := c_white_man;
        v_player_king := c_white_king;
        v_simple_directions := v_simple_move_w;
    ELSE
        v_player_man  := c_black_man;
        v_player_king := c_black_king;
        v_simple_directions := v_simple_move_b;
    END IF;

    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece       CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_start_field rec_board_field := g_map_by_idx(i);
            v_paths       t_move_list;
            v_is_king     CHAR(1);
        BEGIN

            IF v_piece IN (v_player_man, v_player_king) THEN
                v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;

                v_paths := find_capture_paths(i, v_decoded_board, p_player_color, v_is_king, p_rule_id);
                
                IF v_paths.COUNT > 0 THEN
                    FOR j IN 1 .. v_paths.COUNT LOOP
                        v_capture_moves.EXTEND;
                        v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                        IF v_paths(j).capture_count > v_max_captures THEN
                            v_max_captures := v_paths(j).capture_count;
                        END IF;
                    END LOOP;
                END IF;

                IF v_capture_moves.COUNT = 0 THEN
                    IF v_piece = v_player_man THEN

                        FOR d IN 1 .. v_simple_directions.COUNT LOOP
                            DECLARE
                                v_end_idx   PLS_INTEGER := i + v_simple_directions(d);
                                v_end_field rec_board_field;
                            BEGIN

                                IF v_end_idx BETWEEN 1 AND v_total_squares
                                   AND g_map_by_idx.EXISTS(v_end_idx)
                                   AND SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field
                                THEN
                                    v_end_field := g_map_by_idx(v_end_idx);

                                    IF ABS(v_start_field.col_num - v_end_field.col_num) = 1 THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx     := i;
                                            v_step.end_idx       := v_end_idx;
                                            v_step.captured_idx  := NULL;
                                            v_move.path          := t_move_path(v_step);
                                            v_move.is_capture    := 'N';
                                            v_move.capture_count := 0;
                                            v_simple_moves.EXTEND;
                                            v_simple_moves(v_simple_moves.LAST) := v_move;
                                        END;
                                    END IF;
                                END IF;
                            END;
                        END LOOP;
                        
                    ELSIF v_piece = v_player_king THEN

                        FOR d IN 1 .. v_simple_move_all.COUNT LOOP
                            FOR k IN 1 .. v_max_king_range LOOP 
                                DECLARE
                                    v_end_idx   PLS_INTEGER := i + (v_simple_move_all(d) * k);
                                    v_end_field rec_board_field;
                                BEGIN
                                    IF NOT g_map_by_idx.EXISTS(v_end_idx) THEN EXIT; END IF;
                                    v_end_field := g_map_by_idx(v_end_idx);

                                    IF k > 1 AND ABS(g_map_by_idx(i + (v_simple_move_all(d) * (k - 1))).col_num - v_end_field.col_num) != 1 THEN
                                        EXIT;
                                    END IF;

                                    IF SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                        DECLARE
                                            v_move r_move;
                                            v_step r_move_step;
                                        BEGIN
                                            v_step.start_idx     := i;
                                            v_step.end_idx       := v_end_idx;
                                            v_step.captured_idx  := NULL;
                                            v_move.path          := t_move_path(v_step);
                                            v_move.is_capture    := 'N';
                                            v_move.capture_count := 0;
                                            v_simple_moves.EXTEND;
                                            v_simple_moves(v_simple_moves.LAST) := v_move;
                                        END;
                                    ELSE
                                        EXIT;
                                    END IF;
                                END;
                            END LOOP;
                        END LOOP;
                    END IF;
                END IF;
            END IF;
        END;
    END LOOP;

    IF v_capture_moves.COUNT > 0 THEN

        IF p_rule_id = 1 THEN 
            RETURN v_capture_moves;
        ELSE 

            FOR i IN 1 .. v_capture_moves.COUNT LOOP
                IF v_capture_moves(i).capture_count = v_max_captures THEN
                    v_all_moves.EXTEND;
                    v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                END IF;
            END LOOP;
            RETURN v_all_moves;
        END IF;
    END IF;

    RETURN v_simple_moves;
END find_all_player_moves;

FUNCTION apply_move_to_board(
    p_board IN VARCHAR2,
    p_move  IN r_move,
    p_color IN CHAR
) RETURN VARCHAR2 IS
    v_new_board    VARCHAR2(100) := p_board;
    v_moving_piece CHAR(1) := SUBSTR(v_new_board, p_move.path(1).start_idx, 1);
    v_start_pos    PLS_INTEGER := p_move.path(1).start_idx;
    v_end_pos      PLS_INTEGER := p_move.path(p_move.path.LAST).end_idx;
    
    v_total_squares PLS_INTEGER;
    v_board_size    PLS_INTEGER;
BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    p_init_board_map(v_board_size);

    v_new_board := SUBSTR(v_new_board, 1, v_start_pos - 1) || c_empty_field || SUBSTR(v_new_board, v_start_pos + 1);

    IF p_move.is_capture = 'Y' THEN
        FOR i IN 1..p_move.path.COUNT LOOP
            v_new_board := SUBSTR(v_new_board, 1, p_move.path(i).captured_idx - 1) || c_empty_field || SUBSTR(v_new_board, p_move.path(i).captured_idx + 1);
        END LOOP;
    END IF;

    IF v_moving_piece IN (c_white_man, c_black_man) THEN
        DECLARE
            v_promotion_row PLS_INTEGER := CASE p_color WHEN 'W' THEN v_board_size ELSE 1 END;
            v_current_row   PLS_INTEGER;
            v_rule_id       NUMBER := CASE v_board_size WHEN 8 THEN 1 ELSE 2 END;
        BEGIN
            IF v_rule_id = 1 THEN

                FOR i IN 1..p_move.path.COUNT LOOP
                    v_current_row := g_map_by_idx(p_move.path(i).end_idx).row_num;
                    IF v_current_row = v_promotion_row THEN

                        v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                        EXIT;
                    END IF;
                END LOOP;
            ELSE

                v_current_row := g_map_by_idx(v_end_pos).row_num;
                IF v_current_row = v_promotion_row THEN

                    v_moving_piece := CASE p_color WHEN 'W' THEN c_white_king ELSE c_black_king END;
                END IF;
            END IF;
        END;
    END IF;

    v_new_board := SUBSTR(v_new_board, 1, v_end_pos - 1) || v_moving_piece || SUBSTR(v_new_board, v_end_pos + 1);
    RETURN v_new_board;
END apply_move_to_board;

FUNCTION minimax(
    p_board         IN VARCHAR2,
    p_depth         IN PLS_INTEGER,
    p_alpha         IN NUMBER, 
    p_beta          IN NUMBER, 
    p_is_maximizing IN BOOLEAN,
    p_ai_color      IN CHAR,
    p_difficulty    IN CHAR,
    p_rule_id       IN NUMBER
) RETURN r_minimax_result IS
    v_result         r_minimax_result;
    v_possible_moves t_move_list; 
    v_current_color  CHAR(1);
    v_local_alpha    NUMBER := p_alpha;
    v_local_beta     NUMBER := p_beta;

    c_man_value      CONSTANT NUMBER := 10;
    c_king_value     CONSTANT NUMBER := 50;
    c_side_val       CONSTANT NUMBER := 20; 
    c_wall_val       CONSTANT NUMBER := 10;
BEGIN
    v_current_color := CASE p_is_maximizing WHEN TRUE THEN p_ai_color ELSE CASE p_ai_color WHEN 'W' THEN 'B' ELSE 'W' END END;

    v_possible_moves := find_all_player_moves(p_board, v_current_color, p_rule_id);

    IF v_possible_moves.COUNT >= 2 THEN
        DECLARE
            v_temp r_move;
            v_board_size PLS_INTEGER := SQRT(LENGTH(p_board));
            v_end_row PLS_INTEGER;
            v_start_piece CHAR(1);
            v_promotion_row PLS_INTEGER := CASE v_current_color WHEN 'W' THEN v_board_size ELSE 1 END;
        BEGIN

            p_init_board_map(v_board_size);

            FOR i IN 1..v_possible_moves.COUNT LOOP
                v_possible_moves(i).score := 0;

                IF v_possible_moves(i).is_capture = 'Y' THEN
                    v_possible_moves(i).score := 1000 + v_possible_moves(i).capture_count;
                ELSE

                    IF v_possible_moves(i).path.COUNT > 0 THEN
                        v_start_piece := SUBSTR(p_board, v_possible_moves(i).path(1).start_idx, 1);
                        v_end_row := g_map_by_idx(v_possible_moves(i).path(v_possible_moves(i).path.COUNT).end_idx).row_num;

                        IF (v_start_piece IN (c_white_man, c_black_man)) AND (v_end_row = v_promotion_row) THEN
                            v_possible_moves(i).score := 100;
                        END IF;
                    END IF;
                END IF;
            END LOOP;

            FOR i IN 1 .. v_possible_moves.COUNT - 1 LOOP
                FOR j IN i + 1 .. v_possible_moves.COUNT LOOP
                    IF v_possible_moves(i).score < v_possible_moves(j).score THEN
                        v_temp := v_possible_moves(i);
                        v_possible_moves(i) := v_possible_moves(j);
                        v_possible_moves(j) := v_temp;
                    END IF;
                END LOOP;
            END LOOP;
        END;
    END IF;

    IF p_depth = 0 OR v_possible_moves.COUNT = 0 THEN

        DECLARE
            v_score          NUMBER := 0;
            v_piece          CHAR(1);
            v_total_squares  PLS_INTEGER;
            v_board_size     PLS_INTEGER;
            v_ai_pieces_cnt  PLS_INTEGER := 0;
            v_opp_pieces_cnt PLS_INTEGER := 0;
        BEGIN
            v_total_squares := LENGTH(p_board);
            v_board_size    := SQRT(v_total_squares);
            p_init_board_map(v_board_size);

            FOR i IN 1..v_total_squares LOOP
                v_piece := SUBSTR(p_board, i, 1);
                
                IF v_piece != c_empty_field THEN
                    DECLARE
                        v_piece_value    NUMBER;
                        v_multiplier     NUMBER;
                        v_piece_color    CHAR(1);
                        v_field_rec      rec_board_field := g_map_by_idx(i);
                        v_row            PLS_INTEGER     := v_field_rec.row_num;
                        v_col            PLS_INTEGER     := v_field_rec.col_num;
                        v_position_bonus NUMBER := 0;
                    BEGIN
                        v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                        
                        IF v_piece_color = p_ai_color THEN
                            v_ai_pieces_cnt := v_ai_pieces_cnt + 1;
                        ELSE
                            v_opp_pieces_cnt := v_opp_pieces_cnt + 1;
                        END IF;

                        v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                        v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                        
                        v_score := v_score + (v_piece_value * v_multiplier);

                        IF p_difficulty != 'H' THEN
                            IF v_col = 1 OR v_col = v_board_size THEN
                                v_position_bonus := v_position_bonus + c_side_val;
                            END IF;

                            IF v_piece_color = 'W' THEN
                                v_position_bonus := v_position_bonus + ( (v_row / v_board_size) * c_wall_val );
                            ELSE
                                v_position_bonus := v_position_bonus + ( (( (v_board_size + 1) - v_row) / v_board_size) * c_wall_val );
                            END IF;
                        END IF;
                        
                        v_score := v_score + (v_position_bonus * v_multiplier);
                    END;
                END IF;
            END LOOP;
            
            IF v_ai_pieces_cnt > 0 AND v_opp_pieces_cnt = 0 THEN
                v_result.score := 9999;
            ELSIF v_ai_pieces_cnt = 0 AND v_opp_pieces_cnt > 0 THEN
                v_result.score := -9999;
            ELSE
                v_result.score := v_score;
            END IF;
        END;
        
        v_result.move := NULL;
        RETURN v_result;
    END IF;
    
    IF p_is_maximizing THEN
        v_result.score := -99999; 
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => FALSE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );
                
                IF v_eval_result.score > v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;
                
                v_local_alpha := GREATEST(v_local_alpha, v_eval_result.score);
                
                IF v_local_beta <= v_local_alpha THEN
                    EXIT;
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    ELSE
        v_result.score := 99999;
        FOR i IN 1..v_possible_moves.COUNT LOOP
            DECLARE
                v_new_board   VARCHAR2(100) := apply_move_to_board(p_board, v_possible_moves(i), v_current_color);
                v_eval_result r_minimax_result;
            BEGIN
                v_eval_result := minimax(
                    p_board         => v_new_board, 
                    p_depth         => p_depth - 1, 
                    p_alpha         => v_local_alpha, 
                    p_beta          => v_local_beta, 
                    p_is_maximizing => TRUE, 
                    p_ai_color      => p_ai_color, 
                    p_difficulty    => p_difficulty,
                    p_rule_id       => p_rule_id
                );

                IF v_eval_result.score < v_result.score THEN
                    v_result.score := v_eval_result.score;
                    v_result.move  := v_possible_moves(i);
                END IF;

                v_local_beta := LEAST(v_local_beta, v_eval_result.score);

                IF v_local_beta <= v_local_alpha THEN
                    EXIT;
                END IF;
            END;
        END LOOP;
        RETURN v_result;
    END IF;
END minimax;

FUNCTION get_ai_move(
    p_board_position IN game_moves.board_position%TYPE,
    p_ai_color       IN games.current_turn%TYPE,
    p_rule_id        IN games.rule_id%TYPE,
    p_difficulty     IN games.ai_difficulty%TYPE
) RETURN VARCHAR2 IS
    v_best_move_str  VARCHAR2(100);
    v_chosen_move    r_move;
    v_decoded_board  VARCHAR2(100) := decode_board(p_board_position);
    v_search_depth   PLS_INTEGER := 2;
    v_minimax_result r_minimax_result;
    v_alpha          NUMBER;
    v_beta           NUMBER;
    v_board_size     PLS_INTEGER;
BEGIN
    v_board_size := SQRT(LENGTH(v_decoded_board));
    p_init_board_map(v_board_size);

    DECLARE
        v_all_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
        v_capture_count PLS_INTEGER := 0;
    BEGIN

        FOR i IN 1 .. v_all_moves.COUNT LOOP
            IF v_all_moves(i).is_capture = 'Y' THEN
                v_capture_count := v_capture_count + 1;
            END IF;
        END LOOP;

        IF v_capture_count = 1 AND v_all_moves.COUNT = 1 THEN
            v_best_move_str := f_move_to_notation(v_all_moves(1), v_board_size);
            RETURN v_best_move_str;
        END IF;
    END;

    IF p_difficulty = 'M' THEN
        v_search_depth := 4;
    ELSIF p_difficulty = 'H' THEN
        v_search_depth := 8;
    END IF;
    v_alpha := -99999;
    v_beta  := 99999;

    v_minimax_result := minimax(
        p_board         => v_decoded_board, 
        p_depth         => v_search_depth, 
        p_alpha         => v_alpha, 
        p_beta          => v_beta, 
        p_is_maximizing => TRUE, 
        p_ai_color      => p_ai_color, 
        p_difficulty    => p_difficulty,
        p_rule_id       => p_rule_id
    );
    v_chosen_move := v_minimax_result.move;

    IF p_difficulty = 'E' AND DBMS_RANDOM.VALUE < 0.25 THEN
         DECLARE
            v_random_moves t_move_list := find_all_player_moves(v_decoded_board, p_ai_color, p_rule_id);
         BEGIN
            IF v_random_moves.COUNT > 0 THEN
                 v_chosen_move := v_random_moves(TRUNC(DBMS_RANDOM.VALUE(1, v_random_moves.COUNT + 1)));
            END IF;
         END;
     END IF;

    IF v_chosen_move.path IS NOT NULL AND v_chosen_move.path.COUNT > 0 THEN
         v_best_move_str := f_move_to_notation(v_chosen_move, v_board_size);
    ELSE

         v_best_move_str := NULL;
    END IF;

    RETURN v_best_move_str;
END get_ai_move;

FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2
) RETURN CLOB IS
    v_empty_indices t_map_indices;
BEGIN

    RETURN f_get_board_as_clob(p_board_position, v_empty_indices);
END f_get_board_as_clob;

FUNCTION f_get_board_as_clob(
    p_board_position    IN VARCHAR2,
    p_highlight_indices IN t_map_indices
) RETURN CLOB IS
    v_clob          CLOB;
    v_char          CHAR(1);
    v_linear_idx    PLS_INTEGER;
    v_decoded_board VARCHAR2(100) := decode_board(p_board_position);
    
    v_board_size    PLS_INTEGER;
    v_total_squares PLS_INTEGER;
    v_header        VARCHAR2(128) := '  |';
    v_separator     VARCHAR2(128) := '--+';
    
BEGIN
    DBMS_LOB.createtemporary(v_clob, TRUE);

    v_total_squares := LENGTH(v_decoded_board);
    v_board_size    := SQRT(v_total_squares);
    
    IF v_board_size != TRUNC(v_board_size) THEN 
        DBMS_LOB.append(v_clob, 'ОШИБКА: Длина доски (' || v_total_squares || ') не является полным квадратом.');
        RETURN v_clob;
    END IF;
    
    p_init_board_map(v_board_size);
    
    FOR c IN 1 .. v_board_size LOOP

        DECLARE
            v_col_letter CHAR(1);
        BEGIN
            IF c <= 9 THEN
                v_col_letter := CHR(ASCII('A') + c - 1);
            ELSE

                v_col_letter := 'J';
            END IF;
            v_header    := v_header    || ' ' || v_col_letter || ' ';
            v_separator := v_separator || '---';
        END;
    END LOOP;
    v_header    := v_header    || '|';
    v_separator := v_separator || '+--';

    DBMS_LOB.append(v_clob, v_header || c_nl);
    DBMS_LOB.append(v_clob, v_separator || c_nl);

    FOR r IN REVERSE 1 .. v_board_size LOOP
        DBMS_LOB.append(v_clob, LPAD(r, 2, ' ') || '|');
        FOR c IN 1 .. v_board_size LOOP
            v_linear_idx := ((v_board_size - r) * v_board_size) + c;
            
            IF MOD(r + c, 2) = 0 THEN
                v_char := SUBSTR(v_decoded_board, v_linear_idx, 1);
                IF v_char = c_empty_field OR v_char IS NULL THEN
                     IF p_highlight_indices.EXISTS(v_linear_idx) THEN
                         DBMS_LOB.append(v_clob, '[.]');
                     ELSE
                         DBMS_LOB.append(v_clob, '[ ]');
                     END IF;
                ELSE
                    DBMS_LOB.append(v_clob, '[' || v_char || ']');
                END IF;
            ELSE
                DBMS_LOB.append(v_clob, '   ');
            END IF;
        END LOOP;
        DBMS_LOB.append(v_clob, '| ' || r);
        DBMS_LOB.append(v_clob, c_nl);
    END LOOP;
    
    DBMS_LOB.append(v_clob, v_separator || c_nl);
    DBMS_LOB.append(v_clob, v_header || c_nl);
    RETURN v_clob;
END f_get_board_as_clob;

PROCEDURE p_update_ratings(
    p_game_id IN games.game_id%TYPE
) IS
    v_game      games%ROWTYPE;
    v_season_id seasons.season_id%TYPE;
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id;

    BEGIN
        SELECT season_id INTO v_season_id 
        FROM seasons 
        WHERE v_game.start_time BETWEEN start_date AND end_date 
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            SELECT MAX(season_id) INTO v_season_id FROM seasons;
    END;

    IF v_game.status IN ('V', 'T', 'R') AND v_game.match_id IS NULL THEN

        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_solver_id   NUMBER;
                v_prev_solves NUMBER;
                v_puzzle_created_by NUMBER;
                v_is_daily_puzzle BOOLEAN := (v_game.is_daily_puzzle = 'Y');
                v_puzzle_date DATE;
                v_today DATE := TRUNC(SYSDATE);
            BEGIN

                IF v_game.status = 'V' AND v_game.puzzle_status = 's' THEN

                    v_solver_id := CASE WHEN v_game.creator_player_color = 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;

                    SELECT created_by_player_id INTO v_puzzle_created_by
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;

                    IF v_puzzle_created_by IS NULL AND v_solver_id IS NOT NULL THEN

                        IF v_is_daily_puzzle THEN
                            -- Для daily puzzle проверяем, решена ли уже сегодняшняя задача этим игроком
                            BEGIN
                                SELECT dp.puzzle_date INTO v_puzzle_date
                                FROM daily_puzzles dp
                                WHERE dp.puzzle_id = v_game.puzzle_id
                                  AND dp.puzzle_date = v_today
                                  AND ROWNUM = 1;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_puzzle_date := NULL;
                            END;

                            IF v_puzzle_date IS NOT NULL THEN
                                -- Проверяем, решена ли уже сегодняшняя daily puzzle этим игроком
                                SELECT COUNT(*) INTO v_prev_solves
                                FROM games g
                                JOIN daily_puzzles dp ON g.puzzle_id = dp.puzzle_id
                                WHERE dp.puzzle_date = v_today
                                  AND (g.player_white_id = v_solver_id OR g.player_black_id = v_solver_id)
                                  AND g.status = 'V'
                                  AND g.puzzle_status = 's'
                                  AND g.is_daily_puzzle = 'Y'
                                  AND g.game_id != p_game_id;
                            ELSE
                                v_prev_solves := 1; -- Если не найдена сегодняшняя daily puzzle, не начисляем
                            END IF;
                        ELSE
                            -- Для обычных задач проверяем по puzzle_id (как раньше)
                            SELECT COUNT(*) INTO v_prev_solves
                            FROM games
                            WHERE puzzle_id = v_game.puzzle_id
                              AND (player_white_id = v_solver_id OR player_black_id = v_solver_id)
                              AND status = 'V'
                              AND puzzle_status = 's'
                              AND game_id != p_game_id;
                        END IF;

                        IF v_prev_solves = 0 THEN

                            INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                            SELECT v_solver_id, v_game.rule_id, v_season_id, 5
                            FROM DUAL
                            WHERE NOT EXISTS (
                                SELECT 1 FROM player_ratings 
                                WHERE player_id = v_solver_id 
                                  AND rule_id = v_game.rule_id 
                                  AND season_id = v_season_id
                            );
                            
                            UPDATE player_ratings
                            SET rating = GREATEST(0, rating + 5)
                            WHERE player_id = v_solver_id 
                              AND rule_id = v_game.rule_id 
                              AND season_id = v_season_id;
                        END IF;
                    END IF;
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    NULL;
            END;

        ELSE

            IF v_game.ai_difficulty IS NULL THEN

                IF v_game.winner_player_color = 'W' THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + 16)
                    WHERE player_id = v_game.player_white_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating - 16)
                    WHERE player_id = v_game.player_black_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                ELSIF v_game.winner_player_color = 'B' THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + 16)
                    WHERE player_id = v_game.player_black_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating - 16)
                    WHERE player_id = v_game.player_white_id 
                      AND rule_id = v_game.rule_id 
                      AND season_id = v_season_id;
                END IF;
            END IF;

        END IF;
        
    END IF;

END p_update_ratings;

PROCEDURE p_finish_game(
    p_game_id           IN NUMBER,
    p_status            IN CHAR,
    p_winner_color      IN CHAR DEFAULT NULL,
    p_puzzle_status     IN CHAR DEFAULT NULL,
    p_audit_event       IN VARCHAR2,
    p_player_id         IN NUMBER DEFAULT NULL
) IS
    v_game games%ROWTYPE;
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id;

    UPDATE games
    SET status              = p_status,
        end_time            = SYSDATE,
        winner_player_color = p_winner_color,
        puzzle_status       = NVL(p_puzzle_status, puzzle_status)
    WHERE game_id = p_game_id;

    UPDATE spectators 
    SET left_at = SYSDATE 
    WHERE game_id = p_game_id AND left_at IS NULL;

    p_audit_log(p_player_id, p_game_id, p_audit_event);

    IF v_game.match_id IS NULL THEN
        p_update_ratings(p_game_id);
    END IF;

    IF v_game.match_id IS NOT NULL THEN
        DECLARE
            v_match matches%ROWTYPE;
            v_first_game games%ROWTYPE;
            v_player1_id players.player_id%TYPE;
            v_player2_id players.player_id%TYPE;
            v_player1_wins NUMBER := 0;
            v_player2_wins NUMBER := 0;
            v_games_to_win NUMBER;
            v_next_game_id NUMBER;
            v_next_player_color CHAR(1);
            v_season_id seasons.season_id%TYPE;
            v_match_rule_id NUMBER;
        BEGIN
            SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;

            SELECT * INTO v_first_game 
            FROM (
                SELECT * 
                FROM games 
                WHERE match_id = v_game.match_id 
                ORDER BY game_id ASC
            )
            WHERE ROWNUM = 1;
            
            v_player1_id := v_first_game.player_white_id;
            v_player2_id := v_first_game.player_black_id;
            v_games_to_win := v_match.games_to_win;
            v_match_rule_id := v_first_game.rule_id;

            FOR r IN (
                SELECT winner_player_color, status
                FROM games
                WHERE match_id = v_game.match_id
                  AND game_id != p_game_id
                  AND status IN ('V', 'D', 'T', 'R')
            ) LOOP
                IF r.status IN ('V', 'R') THEN
                    IF r.winner_player_color = 'W' THEN
                        v_player1_wins := v_player1_wins + 1;
                    ELSIF r.winner_player_color = 'B' THEN
                        v_player2_wins := v_player2_wins + 1;
                    END IF;
                END IF;
            END LOOP;
            
            IF p_status IN ('V', 'R') AND p_winner_color IS NOT NULL THEN
                IF p_winner_color = 'W' THEN
                    v_player1_wins := v_player1_wins + 1;
                ELSIF p_winner_color = 'B' THEN
                    v_player2_wins := v_player2_wins + 1;
                END IF;
            END IF;

            IF v_match.status = 'C' THEN
                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                IF v_match.winner_player_id = v_player1_id THEN
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player1_wins * 16) + (10 * v_games_to_win))
                    WHERE player_id = v_player1_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player2_wins * 16) - (10 * v_games_to_win))
                    WHERE player_id = v_player2_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                ELSE
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player1_wins * 16) - (10 * v_games_to_win))
                    WHERE player_id = v_player1_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                    
                    UPDATE player_ratings
                    SET rating = GREATEST(0, rating + (v_player2_wins * 16) + (10 * v_games_to_win))
                    WHERE player_id = v_player2_id 
                      AND rule_id = v_match_rule_id 
                      AND season_id = v_season_id;
                END IF;
            ELSIF v_player1_wins >= TRUNC((v_games_to_win + 1) / 2) THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_player1_id
                WHERE match_id = v_game.match_id;
                p_audit_log(v_player1_id, p_game_id, 'MATCH_WON');

                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player1_wins * 16) + (10 * v_games_to_win))
                WHERE player_id = v_player1_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player2_wins * 16) - (10 * v_games_to_win))
                WHERE player_id = v_player2_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
            ELSIF v_player2_wins >= TRUNC((v_games_to_win + 1) / 2) THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_player2_id
                WHERE match_id = v_game.match_id;
                p_audit_log(v_player2_id, p_game_id, 'MATCH_WON');

                BEGIN
                    SELECT season_id INTO v_season_id 
                    FROM seasons 
                    WHERE v_first_game.start_time BETWEEN start_date AND end_date 
                    AND ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        SELECT MAX(season_id) INTO v_season_id FROM seasons;
                END;

                -- Победитель: 16 * победы + 10 * games_to_win
                -- Проигравший: 16 * победы - 10 * games_to_win
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player1_wins * 16) - (10 * v_games_to_win))
                WHERE player_id = v_player1_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
                UPDATE player_ratings
                SET rating = GREATEST(0, rating + (v_player2_wins * 16) + (10 * v_games_to_win))
                WHERE player_id = v_player2_id 
                  AND rule_id = v_match_rule_id 
                  AND season_id = v_season_id;
                
            ELSIF v_match.status != 'C' THEN

                DECLARE
                    v_game_count NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_game_count
                    FROM games
                    WHERE match_id = v_game.match_id;
                    
                    v_next_player_color := CASE WHEN MOD(v_game_count, 2) = 0 THEN 'B' ELSE 'W' END;
                    
                    INSERT INTO games (
                        match_id, rule_id, player_white_id, player_black_id,
                        creator_player_color, status, current_turn,
                        time_limit_move_sec, time_limit_game_sec,
                        draw_moves_limit, enable_pos_repetition_draw
                    )
                    VALUES (
                        v_game.match_id, v_first_game.rule_id,
                        CASE v_next_player_color WHEN 'W' THEN v_player1_id ELSE v_player2_id END,
                        CASE v_next_player_color WHEN 'W' THEN v_player2_id ELSE v_player1_id END,
                        v_next_player_color, 'A', 'W',
                        v_first_game.time_limit_move_sec,
                        v_first_game.time_limit_game_sec,
                        v_first_game.draw_moves_limit,
                        v_first_game.enable_pos_repetition_draw
                    )
                    RETURNING game_id INTO v_next_game_id;
                    
                    p_audit_log(v_player1_id, v_next_game_id, 'MATCH_NEXT_GAME_CREATED');
                END;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
    END IF;
    
    COMMIT;
END p_finish_game;

FUNCTION f_get_current_board_position(
    p_game_id IN NUMBER,
    p_rule_id IN NUMBER
) RETURN VARCHAR2 IS
    v_board_position VARCHAR2(100);
    v_is_puzzle CHAR(1);
    v_puzzle_id NUMBER;
BEGIN
    BEGIN
        SELECT decode_board(board_position) INTO v_board_position
        FROM (
            SELECT board_position
            FROM game_moves
            WHERE game_id = p_game_id
            ORDER BY move_number DESC
        )
        WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN

            BEGIN
                SELECT puzzle_id, puzzle_status INTO v_puzzle_id, v_is_puzzle
                FROM games
                WHERE game_id = p_game_id;

                IF v_is_puzzle = 'p' AND v_puzzle_id IS NOT NULL THEN
                    SELECT decode_board(board_position) INTO v_board_position
                    FROM puzzles
                    WHERE puzzle_id = v_puzzle_id;
                ELSE

                    v_board_position := get_initial_position(p_rule_id);
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN

                    v_board_position := get_initial_position(p_rule_id);
            END;
    END;
    
    RETURN v_board_position;
END f_get_current_board_position;

PROCEDURE p_process_move(
    p_game_id        IN NUMBER,
    p_move_notation  IN VARCHAR2,
    p_player_id      IN NUMBER, 
    p_status_message OUT VARCHAR2
) IS
    v_game              games%ROWTYPE;
    v_player_color      CHAR(1);
    v_all_legal_moves   t_move_list;
    v_chosen_move       r_move;
    v_is_move_valid     BOOLEAN := FALSE;
    v_move_count        NUMBER;
    v_error_msg         VARCHAR2(2000);
    
    v_board_size        PLS_INTEGER;
    v_decoded_board     VARCHAR2(100);
    v_new_board_decoded VARCHAR2(100);
    v_new_board_encoded VARCHAR2(100);

    v_time_delta_sec        NUMBER;
    v_current_player_time   NUMBER;
    v_next_player_time      NUMBER;
    
BEGIN

    SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;

    SELECT r.board_size INTO v_board_size 
    FROM game_rules r 
    WHERE r.rule_id = v_game.rule_id;
    
    p_init_board_map(v_board_size);

    v_decoded_board := f_get_current_board_position(p_game_id, v_game.rule_id);

    IF v_game.ai_difficulty IS NOT NULL THEN
        v_player_color := v_game.current_turn;
    ELSE
        IF v_game.player_white_id = p_player_id THEN
            v_player_color := 'W';
        ELSE
            v_player_color := 'B';
        END IF;
    END IF;

    IF v_game.time_limit_game_sec IS NOT NULL THEN
        DECLARE
            v_player_time_remaining NUMBER;
            v_last_move_time        DATE;
            v_current_time          DATE := SYSDATE;
        BEGIN

            IF v_player_color = 'W' THEN
                v_player_time_remaining := v_game.time_white_remaining_sec;
            ELSE
                v_player_time_remaining := v_game.time_black_remaining_sec;
            END IF;

            IF v_player_time_remaining IS NULL THEN
                v_error_msg := 'Время игрока не инициализировано.';
                p_audit_log(p_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK;
                RETURN;
            END IF;

            BEGIN
                SELECT MAX(move_timestamp) INTO v_last_move_time
                FROM game_moves
                WHERE game_id = p_game_id;
                
                IF v_last_move_time IS NULL THEN
                    v_last_move_time := v_game.start_time;
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_last_move_time := v_game.start_time;
            END;

            v_time_delta_sec := (v_current_time - v_last_move_time) * 86400;

            v_current_player_time := v_player_time_remaining - v_time_delta_sec;

            IF v_current_player_time <= 0 THEN
                p_finish_game(
                    p_game_id      => p_game_id,
                    p_status       => 'T',
                    p_winner_color => CASE WHEN v_player_color = 'W' THEN 'B' ELSE 'W' END,
                    p_audit_event  => 'GAME_TIMEOUT'
                );
                p_status_message := 'Игра завершена по таймауту. У ' || 
                                   CASE WHEN v_player_color = 'W' THEN 'белых' ELSE 'черных' END || 
                                   ' закончилось время.';
                RETURN;
            END IF;
        END;
    END IF;

    v_all_legal_moves := find_all_player_moves(v_decoded_board, v_player_color, v_game.rule_id);

    IF v_all_legal_moves.COUNT = 0 THEN
        p_finish_game(
            p_game_id       => p_game_id,
            p_status        => 'V',
            p_winner_color  => CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
            p_puzzle_status => CASE WHEN v_game.puzzle_id IS NOT NULL THEN 'f' ELSE NULL END,
            p_audit_event   => 'GAME_LOST_NO_MOVES',
            p_player_id     => p_player_id
        );
        p_status_message := 'Ходов нет. Вы проиграли!';
        RETURN;
    END IF;

    FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
        DECLARE
            v_notation VARCHAR2(100) := f_move_to_notation(v_all_legal_moves(i), v_board_size);
        BEGIN
            IF LOWER(p_move_notation) = v_notation THEN
                v_chosen_move   := v_all_legal_moves(i);
                v_is_move_valid := TRUE;
                EXIT;
            END IF;
        END;
    END LOOP;

    IF NOT v_is_move_valid THEN
        IF v_all_legal_moves(1).is_capture = 'Y' THEN
            DECLARE
                v_notation_str VARCHAR2(100);
            BEGIN
                v_error_msg := 'Неверный ход. Взятие обязательно! Доступные варианты: ';
                FOR i IN 1 .. v_all_legal_moves.COUNT LOOP
                    v_notation_str := f_move_to_notation(v_all_legal_moves(i), v_board_size);
                    v_error_msg := v_error_msg || v_notation_str || ' ';
                END LOOP;
                v_error_msg := RTRIM(v_error_msg);
            END;
        ELSE
            v_error_msg := 'Нелегальный ход: "' || p_move_notation || '".';
        END IF;

        p_audit_log(
            p_player_id => p_player_id, 
            p_game_id   => p_game_id, 
            p_event_msg => SUBSTR(v_error_msg, 1, 2000)
        );
        
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        p_status_message := v_error_msg;
        ROLLBACK;
        RETURN;
    END IF;

    v_new_board_decoded := apply_move_to_board(v_decoded_board, v_chosen_move, v_player_color);

    v_new_board_encoded := encode_board(v_new_board_decoded);
    SELECT COUNT(*) + 1 INTO v_move_count FROM game_moves WHERE game_id = p_game_id;

    UPDATE games
    SET current_turn          = CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END,
        draw_offer_status     = NULL, 
        draw_offered_by_color = NULL, 
        draw_offered_at       = NULL
    WHERE game_id = p_game_id;

    INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
    VALUES (p_game_id, v_move_count, p_move_notation, v_chosen_move.is_capture, v_new_board_encoded);

    IF v_game.time_limit_game_sec IS NOT NULL THEN
        DECLARE
            v_next_turn_color       CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
            v_job_name              VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
        BEGIN

            UPDATE games
            SET time_white_remaining_sec = CASE WHEN v_player_color = 'W' 
                                                THEN v_current_player_time 
                                                ELSE time_white_remaining_sec 
                                           END,
                time_black_remaining_sec = CASE WHEN v_player_color = 'B' 
                                                THEN v_current_player_time 
                                                ELSE time_black_remaining_sec 
                                           END
            WHERE game_id = p_game_id;

            SELECT CASE WHEN v_next_turn_color = 'W' 
                       THEN time_white_remaining_sec 
                       ELSE time_black_remaining_sec 
                  END
            INTO v_next_player_time
            FROM games
            WHERE game_id = p_game_id;

            BEGIN
                DBMS_SCHEDULER.SET_ATTRIBUTE(
                    name      => v_job_name,
                    attribute => 'start_date',
                    value     => SYSTIMESTAMP + (GREATEST(1, v_next_player_time) / 86400)
                );
            EXCEPTION
                WHEN OTHERS THEN

                    DBMS_SCHEDULER.CREATE_JOB(
                        job_name   => v_job_name,
                        job_type   => 'PLSQL_BLOCK',
                        job_action => 'DECLARE
                                v_game games%ROWTYPE;
                                v_loser_color CHAR(1);
                            BEGIN
                                BEGIN
                                    SELECT * INTO v_game FROM games WHERE game_id = ' || p_game_id || ' FOR UPDATE;
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        RETURN;
                                END;
                                
                                IF v_game.status != ''A'' THEN
                                    RETURN;
                                END IF;
                                
                                v_loser_color := v_game.current_turn;
                                
                                UPDATE games
                                SET status = ''T'',
                                    end_time = SYSDATE,
                                    winner_player_color = CASE v_loser_color WHEN ''W'' THEN ''B'' ELSE ''W'' END
                                WHERE game_id = ' || p_game_id || ';
                                
                                UPDATE spectators SET left_at = SYSDATE 
                                WHERE game_id = ' || p_game_id || ' AND left_at IS NULL;
                                
                                game_logic.p_update_ratings(' || p_game_id || ');
                                game_logic.p_audit_log(NULL, ' || p_game_id || ', ''GAME_TIMEOUT'');
                                COMMIT;
                            EXCEPTION
                                WHEN OTHERS THEN NULL;
                            END;',
                        start_date => SYSTIMESTAMP + (GREATEST(1, v_next_player_time) / 86400),
                        enabled    => TRUE,
                        auto_drop  => TRUE,
                        comments   => 'Game timeout job for game ' || p_game_id
                    );
            END;
        END;
    ELSIF v_game.time_limit_move_sec IS NOT NULL THEN

        DECLARE
            v_job_name VARCHAR2(128) := 'MOVE_TIMEOUT_JOB_' || p_game_id;
        BEGIN
            DBMS_SCHEDULER.SET_ATTRIBUTE(
                name      => v_job_name,
                attribute => 'start_date',
                value     => SYSTIMESTAMP + (v_game.time_limit_move_sec / 86400)
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END IF;
    
    IF p_player_id IS NULL THEN
        p_status_message := 'Ход(#' || v_move_count || ') ИИ: ' || p_move_notation;
    ELSE
        p_status_message := 'Ход(#' || v_move_count || '): ' || p_move_notation || ' принят.';
    END IF;

    DECLARE
        v_next_turn_color       CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
        v_next_player_moves     t_move_list;
        v_opponent_pieces_exist BOOLEAN := FALSE;
        v_repetition_count      NUMBER;
    BEGIN

        IF v_next_turn_color = 'W' THEN
            v_opponent_pieces_exist := INSTR(v_new_board_decoded, c_white_man) > 0 OR INSTR(v_new_board_decoded, c_white_king) > 0;
        ELSE
            v_opponent_pieces_exist := INSTR(v_new_board_decoded, c_black_man) > 0 OR INSTR(v_new_board_decoded, c_black_king) > 0;
        END IF;

        IF v_game.puzzle_id IS NOT NULL THEN
            DECLARE
                v_puzzle_end_board VARCHAR2(100);
                v_puzzle_moves_to_solve NUMBER;
                v_puzzle_solution VARCHAR2(2000);
                v_current_move_count NUMBER;
                v_encoded_current_board VARCHAR2(100);
                v_solution_msg VARCHAR2(2000);
            BEGIN
                SELECT end_board_state, moves_to_solve, solution
                INTO v_puzzle_end_board, v_puzzle_moves_to_solve, v_puzzle_solution
                FROM puzzles
                WHERE puzzle_id = v_game.puzzle_id;

                v_current_move_count := v_move_count;
                v_encoded_current_board := encode_board(v_new_board_decoded);

                IF v_puzzle_end_board IS NULL THEN

                    IF NOT v_opponent_pieces_exist THEN

                        IF v_puzzle_moves_to_solve IS NOT NULL AND v_current_move_count > v_puzzle_moves_to_solve THEN
                            v_solution_msg := 'Вы решили задачу за ' || v_current_move_count || ' ход(ов), но более оптимальное решение за ' || v_puzzle_moves_to_solve || ' хода(ов): ' || NVL(v_puzzle_solution, 'не указано');
                        ELSE
                            v_solution_msg := 'Поздравляем! Вы решили задачу за ' || v_current_move_count || ' хода(ов)!';
                        END IF;
                        
                        p_finish_game(
                            p_game_id       => p_game_id,
                            p_status        => 'V',
                            p_winner_color  => v_player_color,
                            p_puzzle_status => 's',
                            p_audit_event   => 'PUZZLE_SOLVED',
                            p_player_id     => p_player_id
                        );
                        p_status_message := p_status_message || ' Победа! У противника не осталось фигур.' || c_nl || v_solution_msg;
                        RETURN;
                    END IF;

                    DECLARE
                        v_next_turn_color_puzzle CHAR(1) := CASE v_player_color WHEN 'W' THEN 'B' ELSE 'W' END;
                        v_next_player_moves_puzzle t_move_list;
                    BEGIN
                        v_next_player_moves_puzzle := find_all_player_moves(v_new_board_decoded, v_next_turn_color_puzzle, v_game.rule_id);
                        IF v_next_player_moves_puzzle.COUNT = 0 THEN

                            IF v_puzzle_moves_to_solve IS NOT NULL AND v_current_move_count > v_puzzle_moves_to_solve THEN
                                v_solution_msg := 'Вы решили задачу за ' || v_current_move_count || ' ход(ов), но более оптимальное решение за ' || v_puzzle_moves_to_solve || ' хода(ов): ' || NVL(v_puzzle_solution, 'не указано');
                            ELSE
                                v_solution_msg := 'Поздравляем! Вы решили задачу за ' || v_current_move_count || ' хода(ов)!';
                            END IF;
                            
                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'V',
                                p_winner_color  => v_player_color,
                                p_puzzle_status => 's',
                                p_audit_event   => 'PUZZLE_SOLVED',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Победа! Противник заблокирован.' || c_nl || v_solution_msg;
                            RETURN;
                        END IF;
                    END;
                ELSE

                    IF v_puzzle_moves_to_solve IS NOT NULL THEN
                        IF v_encoded_current_board = v_puzzle_end_board THEN

                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'D',
                                p_puzzle_status => 's',
                                p_audit_event   => 'PUZZLE_SOLVED_DRAW',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Ничья! Достигнута целевая позиция. Задача решена!';
                            RETURN;
                        ELSE

                            p_finish_game(
                                p_game_id       => p_game_id,
                                p_status        => 'D',
                                p_puzzle_status => 'f',
                                p_audit_event   => 'PUZZLE_FAILED_DRAW',
                                p_player_id     => p_player_id
                            );
                            p_status_message := p_status_message || ' Ничья! Достигнуто ' || v_puzzle_moves_to_solve || ' ход(ов), но целевая позиция не достигнута. Задача не решена.';
                            RETURN;
                        END IF;
                    END IF;
                END IF;
            END;
        END IF;
        
        IF NOT v_opponent_pieces_exist THEN
            p_finish_game(
                p_game_id       => p_game_id,
                p_status        => 'V',
                p_winner_color  => v_player_color,
                p_audit_event   => 'WIN_NO_PIECES',
                p_player_id     => p_player_id
            );
            p_status_message := p_status_message || ' Победа! У противника не осталось фигур.';
            RETURN;
        END IF;

        v_next_player_moves := find_all_player_moves(v_new_board_decoded, v_next_turn_color, v_game.rule_id);
        IF v_next_player_moves.COUNT = 0 THEN
            p_finish_game(
                p_game_id       => p_game_id,
                p_status        => 'V',
                p_winner_color  => v_player_color,
                p_audit_event   => 'WIN_PAT',
                p_player_id     => p_player_id
            );
            p_status_message := p_status_message || ' Победа! Противник заблокирован.';
            RETURN;
        END IF;

        IF v_game.draw_moves_limit IS NOT NULL THEN
            DECLARE
                v_moves_without_capture PLS_INTEGER := 0;
                v_last_capture_move PLS_INTEGER := 0;
            BEGIN

                SELECT NVL(MAX(move_number), 0) INTO v_last_capture_move
                FROM game_moves
                WHERE game_id = p_game_id AND is_capture = 'Y';

                SELECT COUNT(*) INTO v_moves_without_capture
                FROM game_moves
                WHERE game_id = p_game_id
                  AND move_number > v_last_capture_move
                  AND is_capture = 'N';

                IF v_chosen_move.is_capture = 'N' THEN
                    v_moves_without_capture := v_moves_without_capture + 1;
                END IF;

                IF v_moves_without_capture >= v_game.draw_moves_limit THEN
                    p_finish_game(
                        p_game_id      => p_game_id,
                        p_status       => 'D',
                        p_audit_event  => 'DRAW_MOVES_LIMIT'
                    );
                    p_status_message := p_status_message || ' Ничья! Превышен лимит ходов без взятия (' || v_game.draw_moves_limit || ').';
                    RETURN;
                END IF;
            END;
        END IF;

        IF v_game.enable_pos_repetition_draw = 'Y' THEN

            DECLARE
                v_next_turn_after_move CHAR(1) := CASE WHEN MOD(v_move_count, 2) = 1 THEN 'B' ELSE 'W' END;
            BEGIN
                SELECT COUNT(*) INTO v_repetition_count 
                FROM game_moves 
                WHERE game_id = p_game_id 
                  AND board_position = v_new_board_encoded
                  AND CASE WHEN MOD(move_number, 2) = 1 THEN 'B' ELSE 'W' END = v_next_turn_after_move;
                  
                IF v_repetition_count >= 2 THEN
                    p_finish_game(
                        p_game_id      => p_game_id,
                        p_status       => 'D',
                        p_audit_event  => 'DRAW_REPETITION'
                    );
                    p_status_message := p_status_message || ' Ничья! Троекратное повторение позиции.';
                    RETURN;
                END IF;
            END;
        END IF;
    END;
    
    COMMIT;
END p_process_move;

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
) IS
    v_current_username    players.username%TYPE := USER;
    v_current_player_id   players.player_id%TYPE;
    v_opponent_player_id  players.player_id%TYPE;
    v_white_player_id     players.player_id%TYPE;
    v_black_player_id     players.player_id%TYPE;
    v_creator_color       CHAR(1);
    v_initial_position    VARCHAR2(100);
    v_encoded_position    VARCHAR2(100);
    v_status              games.status%TYPE;
    v_ai_move             VARCHAR2(50);
    v_ai_msg              VARCHAR2(1000);
    v_game_id             NUMBER;
    v_status_message      VARCHAR2(1000);
    v_my_active_game_id   NUMBER;
    v_error_msg           VARCHAR2(2000);
    v_puzzle_id_to_use    NUMBER;
BEGIN
    v_current_player_id := get_or_create_player_id(v_current_username);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_current_player_id;

    v_my_active_game_id := get_active_game(v_current_player_id);
    IF v_my_active_game_id IS NOT NULL THEN
        v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_my_active_game_id;
        p_audit_log(v_current_player_id, v_my_active_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_time_limit_move_sec IS NOT NULL AND (p_time_limit_move_sec < 30 OR p_time_limit_move_sec > 300) THEN
        v_error_msg := 'Лимит времени на ход должен быть от 30 до 300 секунд (5 минут).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_time_limit_game_sec IS NOT NULL AND (p_time_limit_game_sec < 600 OR p_time_limit_game_sec > 7200) THEN
        v_error_msg := 'Лимит времени на партию должен быть от 600 до 7200 секунд (от 10 до 120 минут).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_draw_moves_limit IS NOT NULL AND (p_draw_moves_limit < 5 OR p_draw_moves_limit > 20) THEN
        v_error_msg := 'Лимит ходов без взятий должен быть от 5 до 20.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_enable_pos_rep_draw IS NOT NULL AND p_enable_pos_rep_draw NOT IN ('Y', 'N') THEN
        v_error_msg := 'Параметр enable_pos_rep_draw должен быть Y или N.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_player_color IS NOT NULL AND p_player_color NOT IN ('W', 'B') THEN
        v_error_msg := 'Цвет игрока должен быть W (белые) или B (черные).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_ai_difficulty IS NOT NULL AND p_ai_difficulty NOT IN ('E', 'M', 'H') THEN
        v_error_msg := 'Некорректная сложность ИИ. Допустимые значения: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (p_opponent_username IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_ai_difficulty IS NOT NULL) OR
       (p_puzzle_id IS NOT NULL AND p_opponent_username IS NOT NULL)
    THEN
        v_error_msg := 'Конфликт параметров. Нельзя одновременно создавать Задачу, PVE и PVP.';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_ai_difficulty IS NOT NULL AND (p_time_limit_move_sec IS NOT NULL OR p_time_limit_game_sec IS NOT NULL) THEN
        v_error_msg := 'Игры против ИИ не могут иметь таймауты (time_limit_move_sec или time_limit_game_sec).';
        p_audit_log(v_current_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_puzzle_id IS NOT NULL THEN
        IF p_time_limit_move_sec IS NOT NULL OR p_time_limit_game_sec IS NOT NULL OR 
           p_draw_moves_limit IS NOT NULL OR p_enable_pos_rep_draw != 'N' OR
           p_player_color IS NOT NULL THEN
            v_error_msg := 'Задачи не могут иметь таймауты, лимиты ходов, повтор позиций или выбор цвета.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    END IF;

    IF p_daily = 'Y' THEN
        IF p_puzzle_id IS NOT NULL THEN
            v_error_msg := 'Нельзя одновременно передавать p_daily и p_puzzle_id.';
            p_audit_log(v_current_player_id, NULL, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        DECLARE
            v_today     DATE := TRUNC(SYSDATE);
            v_count     PLS_INTEGER;
            v_new_puzzle_id puzzles.puzzle_id%TYPE;
        BEGIN

            SELECT COUNT(*) INTO v_count FROM daily_puzzles WHERE puzzle_date = v_today;
            
            IF v_count = 0 THEN

                BEGIN

                    SELECT puzzle_id INTO v_new_puzzle_id
                    FROM (
                        SELECT p.puzzle_id
                        FROM puzzles p
                        LEFT JOIN daily_puzzles dp ON p.puzzle_id = dp.puzzle_id AND dp.puzzle_date >= (v_today - 30)
                        WHERE p.created_by_player_id IS NULL
                        AND dp.puzzle_id IS NULL             
                        ORDER BY DBMS_RANDOM.VALUE
                    ) WHERE ROWNUM = 1;
                    
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN

                        BEGIN
                            SELECT puzzle_id INTO v_new_puzzle_id
                            FROM (
                                SELECT puzzle_id FROM puzzles 
                                WHERE created_by_player_id IS NULL
                                ORDER BY DBMS_RANDOM.VALUE
                            ) WHERE ROWNUM = 1;
                        END;
                END;

                INSERT INTO daily_puzzles (puzzle_date, puzzle_id) VALUES (v_today, v_new_puzzle_id);
                v_puzzle_id_to_use := v_new_puzzle_id;
                DBMS_OUTPUT.PUT_LINE('Daily Puzzle на сегодня успешно создан (ID: ' || v_new_puzzle_id || ').');
            ELSE

                SELECT puzzle_id INTO v_puzzle_id_to_use
                FROM daily_puzzles
                WHERE puzzle_date = v_today
                AND ROWNUM = 1;
            END IF;
        END;
    ELSE

        v_puzzle_id_to_use := p_puzzle_id;
    END IF;

    IF v_puzzle_id_to_use IS NOT NULL THEN
        DECLARE
            v_puzzle puzzles%ROWTYPE;
        BEGIN
            SELECT * INTO v_puzzle FROM puzzles WHERE puzzle_id = v_puzzle_id_to_use;
            v_initial_position := v_puzzle.board_position;
            v_encoded_position := encode_board(v_initial_position);
            v_status := 'A';

            IF v_puzzle.turn_to_move = 'W' THEN
                v_white_player_id := v_current_player_id;
                v_black_player_id := NULL;
                v_creator_color   := 'W';
            ELSE
                v_white_player_id := NULL;
                v_black_player_id := v_current_player_id;
                v_creator_color   := 'B';
            END IF;

            DECLARE
                v_ai_difficulty_for_puzzle CHAR(1);
            BEGIN

                IF v_puzzle.created_by_player_id IS NULL THEN
                    v_ai_difficulty_for_puzzle := 'M';
                ELSE
                    v_ai_difficulty_for_puzzle := v_puzzle.difficulty_level;
                END IF;
                
                INSERT INTO games (
                    rule_id, player_white_id, player_black_id, 
                    creator_player_color,
                    status, current_turn,
                    puzzle_id, is_daily_puzzle, puzzle_status,
                    ai_difficulty
                )
                VALUES (
                    v_puzzle.rule_id, v_white_player_id, v_black_player_id, 
                    v_creator_color,
                    v_status, v_puzzle.turn_to_move,
                    v_puzzle_id_to_use, p_daily, 'p',
                    v_ai_difficulty_for_puzzle
                )
                RETURNING game_id INTO v_game_id;
            END;
            
            v_status_message := 'Вы начали задачу ID ' || v_puzzle_id_to_use || '. (ID сессии: ' || v_game_id || ').';
            p_audit_log(v_current_player_id, v_game_id, 'START_PUZZLE');
        
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Задача с ID ' || v_puzzle_id_to_use || ' не найдена.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;

    ELSIF p_puzzle_id IS NULL THEN
    
        DECLARE
            v_color_choice CHAR(1) := NVL(UPPER(p_player_color), CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'W' ELSE 'B' END);
        BEGIN
            v_creator_color := v_color_choice;
            IF v_color_choice = 'W' THEN
                v_white_player_id := v_current_player_id;
            ELSE
                v_black_player_id := v_current_player_id;
            END IF;
        END;

        v_initial_position := get_initial_position(p_rule_id);
        IF v_initial_position IS NULL THEN
            RETURN;
        END IF;
        v_encoded_position := encode_board(v_initial_position);

        IF p_ai_difficulty IS NOT NULL THEN
            v_status := 'A';

            IF v_white_player_id IS NULL THEN v_white_player_id := NULL; ELSE v_black_player_id := NULL; END IF;

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                p_ai_difficulty, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Игра против ИИ создана (ID: ' || v_game_id || '). Вы играете за ' || CASE WHEN v_white_player_id = v_current_player_id THEN 'белых (W)' ELSE 'черных (B)' END || '.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_PVE_GAME');

            IF v_white_player_id IS NULL THEN
                v_ai_move := get_ai_move(v_encoded_position, 'W', p_rule_id, p_ai_difficulty);
                IF v_ai_move IS NOT NULL THEN
                    p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                    v_status_message := v_status_message || ' ИИ начинает с хода: ' || v_ai_move;
                END IF;
            END IF;

        ELSIF p_opponent_username IS NOT NULL THEN
            IF v_current_username = UPPER(p_opponent_username) THEN 
                v_error_msg := 'Нельзя вызвать самого себя.';
                p_audit_log(v_current_player_id, NULL, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
            END IF;
            
            BEGIN
                SELECT player_id INTO v_opponent_player_id
                FROM players
                WHERE username = UPPER(TRIM(p_opponent_username));
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_error_msg := 'Оппонент не найден.';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
            END;

            DECLARE
                v_opp_active_game NUMBER := get_active_game(v_opponent_player_id);
            BEGIN
                IF v_opp_active_game IS NOT NULL THEN
                    v_error_msg := 'Игрок "' || p_opponent_username || '" уже занят в другой партии (ID: '|| v_opp_active_game ||').';
                    p_audit_log(v_current_player_id, NULL, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    RETURN;
                END IF;
            END;

            IF v_white_player_id IS NULL THEN v_white_player_id := v_opponent_player_id; ELSE v_black_player_id := v_opponent_player_id; END IF;
            v_status := 'C';

            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вызов игроку ' || p_opponent_username || ' брошен. Game ID: ' || v_game_id || '. Ожидайте принятия.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_CHALLENGE');

        ELSE
            v_status := 'O';
            INSERT INTO games (
                creator_player_color, rule_id, player_white_id, player_black_id, status, current_turn, 
                ai_difficulty, time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                v_creator_color, p_rule_id, v_white_player_id, v_black_player_id, v_status, 'W',
                NULL, p_time_limit_move_sec, p_time_limit_game_sec,
                p_draw_moves_limit, p_enable_pos_rep_draw
            )
            RETURNING game_id INTO v_game_id;

            v_status_message := 'Вы создали открытую игру. Game ID: ' || v_game_id || '. Ожидайте оппонента.';
            p_audit_log(v_current_player_id, v_game_id, 'CREATE_OPEN_GAME');
        END IF;
        
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(v_status_message);

    IF (p_ai_difficulty IS NOT NULL AND v_white_player_id IS NULL) OR (v_puzzle_id_to_use IS NOT NULL) THEN
        print_active_board(
            p_game_id => v_game_id,
            p_username => NULL,
            p_wait_for_turn => 'N'
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_game: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Неизвестная ошибка при создании игры: ' || SQLERRM);
END create_game;

PROCEDURE join_game(p_game_id IN NUMBER) IS
    v_game             games%ROWTYPE;
    v_player_id        players.player_id%TYPE;
    v_active_game_id   NUMBER;
    v_error_msg        VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = p_game_id FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    IF v_game.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Нельзя присоединиться к этой игре (ID: ' || p_game_id || ', статус: '|| v_game.status || ').';
        p_audit_log(v_player_id, p_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    DECLARE
        v_creator_id players.player_id%TYPE;
    BEGIN

        IF v_game.creator_player_color = 'W' THEN
            v_creator_id := v_game.player_white_id;
        ELSE
            v_creator_id := v_game.player_black_id;
        END IF;

        IF v_player_id = v_creator_id THEN
            v_error_msg := 'Нельзя присоединиться к собственной игре (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        IF v_game.status = 'C' THEN
            IF v_game.player_white_id IS NOT NULL AND v_game.player_black_id IS NOT NULL THEN

                IF v_player_id NOT IN (v_game.player_white_id, v_game.player_black_id) THEN
                    v_error_msg := 'Доступ запрещен. Этот вызов (ID: ' || p_game_id || ') предназначен не вам.';
                    p_audit_log(v_player_id, p_game_id, v_error_msg);
                    DBMS_OUTPUT.PUT_LINE(v_error_msg);
                    ROLLBACK; 
                    RETURN;
                END IF;
            END IF;
        END IF;
    END;

    IF v_game.status = 'O' THEN

        v_active_game_id := get_active_game(v_player_id);
        IF v_active_game_id IS NOT NULL AND v_active_game_id != p_game_id THEN
            v_error_msg := 'Вы уже участвуете в активной игре. ID вашей игры: ' || v_active_game_id;
            p_audit_log(v_player_id, v_active_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET player_white_id = NVL(v_game.player_white_id, v_player_id),
            player_black_id = NVL(v_game.player_black_id, v_player_id),
            status          = 'A',
            start_time      = SYSDATE,
            time_white_remaining_sec = time_limit_game_sec,
            time_black_remaining_sec = time_limit_game_sec
        WHERE game_id = p_game_id;
    ELSE

        UPDATE games
        SET status                  = 'A',
            start_time              = SYSDATE,
            time_white_remaining_sec = time_limit_game_sec,
            time_black_remaining_sec = time_limit_game_sec
        WHERE game_id = p_game_id;
    END IF;

    BEGIN
        DECLARE
            v_time_limit_game NUMBER;
            v_job_name        VARCHAR2(128);
            v_current_turn    CHAR(1);
            v_time_remaining  NUMBER;
        BEGIN
            SELECT time_limit_game_sec, current_turn,
                   CASE current_turn WHEN 'W' THEN time_white_remaining_sec ELSE time_black_remaining_sec END
            INTO v_time_limit_game, v_current_turn, v_time_remaining
            FROM games
            WHERE game_id = p_game_id;
            
            IF v_time_limit_game IS NOT NULL AND v_time_remaining IS NOT NULL THEN
                v_job_name := 'MOVE_TIMEOUT_JOB_' || p_game_id;

                DBMS_SCHEDULER.CREATE_JOB(
                    job_name   => v_job_name,
                    job_type   => 'PLSQL_BLOCK',
                    job_action => 'DECLARE
                            v_game games%ROWTYPE;
                            v_loser_color CHAR(1);
                        BEGIN
                            BEGIN
                                SELECT * INTO v_game FROM games WHERE game_id = ' || p_game_id || ' FOR UPDATE;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    RETURN;
                            END;
                            
                            IF v_game.status != ''A'' THEN
                                RETURN;
                            END IF;
                            
                            v_loser_color := v_game.current_turn;
                            
                            UPDATE games
                            SET status = ''T'',
                                end_time = SYSDATE,
                                winner_player_color = CASE v_loser_color WHEN ''W'' THEN ''B'' ELSE ''W'' END
                            WHERE game_id = ' || p_game_id || ';
                            
                            UPDATE spectators SET left_at = SYSDATE 
                            WHERE game_id = ' || p_game_id || ' AND left_at IS NULL;
                            
                            game_logic.p_update_ratings(' || p_game_id || ');
                            game_logic.p_audit_log(NULL, ' || p_game_id || ', ''GAME_TIMEOUT'');
                            COMMIT;
                        EXCEPTION
                            WHEN OTHERS THEN NULL;
                        END;',
                    start_date => SYSTIMESTAMP + (GREATEST(1, v_time_remaining) / 86400),
                    enabled    => TRUE,
                    auto_drop  => TRUE,
                    comments   => 'Game timeout job for game ' || p_game_id
                );
            END IF;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END;
    
    p_audit_log(v_player_id, p_game_id, 'JOIN_GAME');

    IF v_game.match_id IS NOT NULL THEN
        DECLARE
            v_match matches%ROWTYPE;
        BEGIN
            SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;
            DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || ' (часть матча ID ' || v_game.match_id || ', Best of ' || v_match.games_to_win || ').');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
        END;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Вы успешно присоединились к игре ID ' || p_game_id || '.');
    END IF;
    
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при присоединении к игре: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 2000));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END join_game;

PROCEDURE resign_game(p_resign_match IN CHAR DEFAULT 'N') IS
    v_game        games%ROWTYPE;
    v_player_id   players.player_id%TYPE;
    v_game_id     NUMBER;
    v_error_msg   VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(user);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
        v_game_id   := get_active_game(v_player_id);

    DECLARE
        v_spectating_game_id NUMBER;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_spectating_game_id := NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя сдаться.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    IF v_game_id IS NULL THEN
        v_error_msg := 'У вас нет активной партии, чтобы сдаться.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status NOT IN ('A') THEN
        v_error_msg := 'Эта партия (ID: ' || v_game_id || ') неактивна (статус '||v_game.status||'). Используйте cancel_game для отмены вызова.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.puzzle_id IS NOT NULL THEN
        p_finish_game(
            p_game_id       => v_game_id,
            p_status        => 'V',
            p_puzzle_status => 'f',
            p_audit_event   => 'QUIT_PUZZLE',
            p_player_id     => v_player_id
        );
        DBMS_OUTPUT.PUT_LINE('[OK] Вы вышли из попытки решения задачи (ID сессии: ' || v_game_id || ').');

    ELSE
        DECLARE
            v_winner_id       players.player_id%TYPE;
            v_winner_color    CHAR(1);
            v_winner_username players.username%TYPE;
        BEGIN
            IF v_player_id = v_game.player_white_id THEN
                v_winner_id := v_game.player_black_id;
                v_winner_color := 'B';
            ELSE
                v_winner_id := v_game.player_white_id;
                v_winner_color := 'W';
            END IF;

            IF UPPER(p_resign_match) = 'Y' AND v_game.match_id IS NOT NULL THEN
                UPDATE matches
                SET status = 'C',
                    winner_player_id = v_winner_id
                WHERE match_id = v_game.match_id;
                
                p_audit_log(v_player_id, v_game.game_id, p_event_msg => 'MATCH_RESIGN');
                DBMS_OUTPUT.PUT_LINE('Вы также сдались во всем матче (ID: ' || v_game.match_id || ').');
            END IF;

            IF v_winner_id IS NOT NULL THEN
                SELECT username INTO v_winner_username FROM players WHERE player_id = v_winner_id;
            ELSE
                v_winner_username := 'AI (Server)';
            END IF;
            
            p_finish_game(
                p_game_id      => v_game_id,
                p_status       => 'R',
                p_winner_color => v_winner_color,
                p_audit_event  => 'RESIGN_GAME',
                p_player_id    => v_player_id
            ); 
            DBMS_OUTPUT.PUT_LINE('[OK] Вы сдались в партии ' || v_game_id || '. Победитель: ' || v_winner_username || '.');
        END;
    END IF;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END resign_game;

PROCEDURE watch_game_replay(
    p_game_id       IN NUMBER,
    p_moves_to_show IN NUMBER DEFAULT 1,
    p_restart       IN CHAR   DEFAULT 'N'
) IS
    v_player_id      players.player_id%TYPE;
    v_seq_name       VARCHAR2(64);
    v_job_name       VARCHAR2(64);
    v_move_num       NUMBER;
    v_color_str      VARCHAR2(30);
    v_session_exists PLS_INTEGER;
    v_game_rec       games%ROWTYPE;
    v_max_moves      NUMBER;
    v_winner_name    players.username%TYPE;
    v_loser_name     players.username%TYPE;
    v_final_message  VARCHAR2(250);
    v_error_msg      VARCHAR2(2000);
    v_replay_finished BOOLEAN := FALSE;
    
    CURSOR c_game_moves (cp_game_id NUMBER, cp_move_number NUMBER) IS
        SELECT
            move_player_username AS username,
            move_player_color AS player_color,
            move_notation,
            board_position
        FROM v_game_protocol
        WHERE game_id = cp_game_id AND move_number = cp_move_number;

BEGIN
    v_player_id := get_or_create_player_id(USER);
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
    
    v_seq_name  := 'REPLAY_SEQ_' || p_game_id || '_' || v_player_id;
    v_job_name  := 'DROP_REPLAY_SEQ_' || p_game_id || '_' || v_player_id;

    SELECT COUNT(*) INTO v_session_exists 
    FROM user_sequences 
    WHERE sequence_name = v_seq_name;

    IF UPPER(p_restart) = 'Y' AND v_session_exists > 0 THEN
        DBMS_OUTPUT.PUT_LINE('--[ Перезапуск просмотра с начала для игры ' || p_game_id || ' ]--');

        BEGIN 
            DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); 
        EXCEPTION 
            WHEN OTHERS THEN NULL; 
        END;

        BEGIN
            EXECUTE IMMEDIATE 'DROP SEQUENCE ' || v_seq_name;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        v_session_exists := 0;
    END IF;

    IF v_session_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('--[ Создание новой сессии просмотра для игры ' || p_game_id || ' ]--');
        
        BEGIN
            SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Игра с ID ' || p_game_id || ' не найдена.';
                p_audit_log(v_player_id, p_game_id, v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        
        IF v_game_rec.status IN ('A', 'O', 'C') THEN
            v_error_msg := 'Нельзя просматривать активную (или не начатую) партию (ID: ' || p_game_id || ').';
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        SELECT count(*) INTO v_max_moves FROM game_moves WHERE game_id = p_game_id;
        IF v_max_moves <= 1 THEN
            IF v_max_moves = 0 THEN
                v_error_msg := 'В этой партии (ID: ' || p_game_id || ') не было ходов. Показана финальная позиция партии.';
            ELSE
                v_error_msg := 'В этой партии (ID: ' || p_game_id || ') был только 1 ход. Пошаговый реплей не создается, показана финальная позиция партии.';
            END IF;
            p_audit_log(v_player_id, p_game_id, v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);

            -- Просто показать текущую/финальную доску без создания сессии реплея
            print_active_board(p_game_id => p_game_id);
            RETURN;
        END IF;

        BEGIN DBMS_SCHEDULER.DROP_JOB(v_job_name, force => TRUE); EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || v_seq_name || 
                              ' START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE ' || 
                              v_max_moves || ' NOCYCLE NOCACHE';
        EXCEPTION
            WHEN OTHERS THEN
                v_error_msg := 'Не удалось создать последовательность ' || v_seq_name || ': ' || SQLERRM;
                p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 2000));
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;

        DBMS_SCHEDULER.create_job(
            job_name   => v_job_name,
            job_type   => 'PLSQL_BLOCK',
            job_action => 'BEGIN EXECUTE IMMEDIATE ''DROP SEQUENCE ' || v_seq_name || '''; END;',
            start_date => SYSTIMESTAMP + INTERVAL '24' HOUR,
            enabled    => TRUE,
            auto_drop  => TRUE,
            comments   => 'Drop replay sequence for game ' || p_game_id || ' player ' || v_player_id
        );
        COMMIT;
        
    END IF;

    IF v_game_rec.game_id IS NULL THEN
         SELECT * INTO v_game_rec FROM games WHERE game_id = p_game_id;
    END IF;

    FOR i IN 1 .. p_moves_to_show LOOP
        BEGIN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT ' || v_seq_name || '.NEXTVAL FROM DUAL' INTO v_move_num;
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE = -8004 THEN
                        v_replay_finished := TRUE;
                    ELSE
                        v_error_msg := 'Ошибка сессии просмотра (ID: ' || p_game_id || '). ' || SQLERRM;
                        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 2000));
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        EXIT;
                    END IF;
            END;

            IF v_replay_finished THEN

                BEGIN
                    IF v_game_rec.status = 'D' THEN
                        v_final_message := 'Ничья.';
                    ELSIF v_game_rec.status = 'T' THEN
                        v_final_message := 'Игра завершена по таймауту.';
                    ELSIF v_game_rec.status IN ('V', 'R') THEN 
                        DECLARE
                            v_winner_id players.player_id%TYPE;
                            v_loser_id  players.player_id%TYPE;
                        BEGIN
                            IF v_game_rec.winner_player_color = 'W' THEN
                                v_winner_id := v_game_rec.player_white_id;
                                v_loser_id  := v_game_rec.player_black_id;
                            ELSE
                                v_winner_id := v_game_rec.player_black_id;
                                v_loser_id  := v_game_rec.player_white_id;
                            END IF;
                            
                            BEGIN 
                                SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; 
                            EXCEPTION 
                                WHEN NO_DATA_FOUND THEN 
                                    v_winner_name := 'AI (difficulty_level: ' || NVL(v_game_rec.ai_difficulty, 'N') || ')'; 
                            END;
                            BEGIN 
                                SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id; 
                            EXCEPTION 
                                WHEN NO_DATA_FOUND THEN 
                                    v_loser_name := 'AI (difficulty_level: ' || NVL(v_game_rec.ai_difficulty, 'N') || ')'; 
                            END;

                            IF v_game_rec.status = 'R' THEN
                                v_final_message := v_loser_name || ' сдался. Победитель: ' || v_winner_name || '.';
                            ELSE
                                v_final_message := 'Победа игрока ' || v_winner_name || '.';
                            END IF;
                        END;
                    ELSE
                        v_final_message := 'Игра завершена (Статус: ' || v_game_rec.status || ').';
                    END IF;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_final_message := 'Игра не найдена.';
                END;
                
                DBMS_OUTPUT.PUT_LINE('--[ КОНЕЦ ПАРТИИ ]-- ' || v_final_message);
                EXIT;
            END IF;

            DECLARE
                v_move_username players.username%TYPE;
                v_move_color CHAR(1);
                v_move_notation VARCHAR2(100);
                v_move_board_position VARCHAR2(100);
            BEGIN
                SELECT 
                    move_player_username,
                    move_player_color,
                    move_notation,
                    board_position
                INTO
                    v_move_username,
                    v_move_color,
                    v_move_notation,
                    v_move_board_position
                FROM v_game_protocol
                WHERE game_id = p_game_id AND move_number = v_move_num
                AND ROWNUM = 1;
                
                v_color_str := CASE v_move_color WHEN 'W' THEN '(Белые)' ELSE '(Черные)' END;
                DBMS_OUTPUT.PUT_LINE('---');
                DBMS_OUTPUT.PUT_LINE(
                    'Ход ' || v_move_num || ' ' || 
                    RPAD(NVL(v_move_username, 'AI'), 20) || ' ' ||
                    RPAD(v_color_str, 10) || ' : ' || 
                    v_move_notation
                );
                DBMS_OUTPUT.PUT_LINE(f_get_board_as_clob(decode_board(v_move_board_position)));
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    DBMS_OUTPUT.PUT_LINE('Ход ' || v_move_num || ' не найден.');
            END;

        END;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Ошибка в watch_game_replay: ' || SQLERRM;
        p_audit_log(v_player_id, p_game_id, SUBSTR(v_error_msg, 1, 2000));
        RAISE;
END watch_game_replay;

PROCEDURE stop_spectating IS
    v_player_id players.player_id%TYPE;
    v_game_id   games.game_id%TYPE;
BEGIN
    v_player_id := get_or_create_player_id(USER);

    BEGIN
        SELECT game_id
        INTO v_game_id
        FROM spectators
        WHERE player_id = v_player_id
          AND left_at IS NULL
        AND ROWNUM = 1;

        UPDATE spectators
        SET left_at = SYSDATE
        WHERE player_id = v_player_id
          AND left_at IS NULL;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Вы вышли из режима просмотра (ID игры = ' || v_game_id || ').');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Вы не находитесь в режиме просмотра.');
    END;
    
END stop_spectating;

PROCEDURE print_active_board(
    p_game_id       IN NUMBER   DEFAULT NULL,
    p_username      IN VARCHAR2 DEFAULT NULL,
    p_wait_for_turn IN CHAR     DEFAULT 'N'
) IS
    v_target_game_id   games.game_id%TYPE;
    v_target_user_id   players.player_id%TYPE;
    v_target_username  players.username%TYPE;
    v_game             games%ROWTYPE;
    v_printable_board  CLOB;
    v_status_header    VARCHAR2(200);
    v_player_username  players.username%TYPE;
    v_move_count       NUMBER;
    v_error_msg        VARCHAR2(2000);
    v_viewer_player_id players.player_id%TYPE;
    
    v_my_color         CHAR(1);
    v_loop_start_time  DATE;
    v_timeout_sec      NUMBER;
    v_wait_message     VARCHAR2(200);

    v_board_size       PLS_INTEGER;

BEGIN
    v_viewer_player_id := get_or_create_player_id(USER);
    
    IF p_game_id IS NOT NULL AND p_username IS NOT NULL THEN
        v_error_msg := 'Для поиска передайте процедуре только один параметр (имя пользователя или id игры).';
        p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    ELSIF p_game_id IS NOT NULL THEN
        v_target_game_id := p_game_id;
    ELSIF p_username IS NOT NULL THEN
        v_target_username := UPPER(p_username);
        BEGIN
            SELECT player_id INTO v_target_user_id FROM players WHERE username = v_target_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_error_msg := 'Пользователя "' || p_username || '" не существует.';
                p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                RETURN;
        END;
        v_target_game_id := get_active_game(v_target_user_id);
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У пользователя "' || p_username || '" не найдено активных сессий.';
            p_audit_log(v_viewer_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    ELSE
        v_target_user_id := v_viewer_player_id; 
        v_target_game_id := get_active_game(v_target_user_id); 
        IF v_target_game_id IS NULL THEN
            v_error_msg := 'У вас нет активных игр.';
            p_audit_log(v_target_user_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
    END IF;

    BEGIN
        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Игры с id = ' || v_target_game_id || ' не существует.';
            p_audit_log(v_viewer_player_id, v_target_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    DECLARE
        v_existing_spectator_game_id NUMBER;
        v_closed_sessions_count NUMBER := 0;
    BEGIN
        BEGIN
            SELECT game_id INTO v_existing_spectator_game_id
            FROM spectators
            WHERE player_id = v_viewer_player_id
              AND left_at IS NULL
              AND game_id != v_target_game_id
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_existing_spectator_game_id := NULL;
        END;

        UPDATE spectators
        SET left_at = SYSDATE
        WHERE player_id = v_viewer_player_id
          AND left_at IS NULL
          AND game_id != v_target_game_id;
        
        v_closed_sessions_count := SQL%ROWCOUNT;
        
        IF v_closed_sessions_count > 0 THEN
            IF v_closed_sessions_count = 1 AND v_existing_spectator_game_id IS NOT NULL THEN
                DBMS_OUTPUT.PUT_LINE('--[ Вы вышли из сессии просмотра игры (ID: ' || v_existing_spectator_game_id || ') ]--');
            ELSIF v_closed_sessions_count > 1 THEN
                DBMS_OUTPUT.PUT_LINE('--[ Вы вышли из ' || v_closed_sessions_count || ' сессий просмотра ]--');
            END IF;
        END IF;
    END;

    IF (v_game.player_white_id IS NULL OR v_viewer_player_id != v_game.player_white_id)
       AND (v_game.player_black_id IS NULL OR v_viewer_player_id != v_game.player_black_id)
       AND v_game.status IN ('A', 'O', 'C')
    THEN

        DECLARE
            v_existing_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_existing_count
            FROM spectators
            WHERE player_id = v_viewer_player_id
              AND game_id = v_target_game_id
              AND left_at IS NULL;
            
            IF v_existing_count = 0 THEN

                INSERT INTO spectators (player_id, game_id, joined_at)
                VALUES (v_viewer_player_id, v_target_game_id, SYSDATE);
                
                p_audit_log(v_viewer_player_id, v_target_game_id, 'SPECTATOR_JOIN');
                DBMS_OUTPUT.PUT_LINE('--[ Вы вошли в режим просмотра (ID: ' || v_target_game_id || ') ]--');
                DBMS_OUTPUT.PUT_LINE('--[ Для отмены вызовите: game_logic.stop_spectating; ]--');
            END IF;
        END;
    END IF;
    
    COMMIT;

    DECLARE
        v_active_player_id  players.player_id%TYPE;
        v_highlight_indices t_map_indices;
        v_legal_moves       t_move_list;
        v_decoded_board     VARCHAR2(100);
    BEGIN
        IF v_game.player_white_id = v_viewer_player_id THEN
            v_my_color := 'W';
        ELSIF v_game.player_black_id = v_viewer_player_id THEN
            v_my_color := 'B';
        ELSE
            v_my_color := NULL; 
        END IF;

        DECLARE
            v_waited_for_connection BOOLEAN := FALSE;
        BEGIN
            IF v_game.status IN ('O', 'C') THEN
                IF UPPER(p_wait_for_turn) = 'Y' THEN

                    v_waited_for_connection := TRUE;
                    DECLARE
                        v_initial_white_id games.player_white_id%TYPE := v_game.player_white_id;
                        v_initial_black_id games.player_black_id%TYPE := v_game.player_black_id;
                        v_connected_player_id players.player_id%TYPE;
                        v_connected_username players.username%TYPE;
                        v_connected_color CHAR(1);
                    BEGIN
                        v_loop_start_time := SYSDATE;
                        v_timeout_sec := 300;

                        WHILE v_game.status IN ('O', 'C')
                        AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400)
                        LOOP
                            SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;

                            IF (v_game.player_white_id IS NOT NULL AND v_game.player_white_id != v_initial_white_id) OR
                               (v_game.player_black_id IS NOT NULL AND v_game.player_black_id != v_initial_black_id)
                            THEN

                                IF v_game.player_white_id IS NOT NULL AND v_game.player_white_id != v_initial_white_id THEN
                                    v_connected_player_id := v_game.player_white_id;
                                    v_connected_color := 'W';
                                ELSIF v_game.player_black_id IS NOT NULL AND v_game.player_black_id != v_initial_black_id THEN
                                    v_connected_player_id := v_game.player_black_id;
                                    v_connected_color := 'B';
                                END IF;

                                BEGIN
                                    SELECT username INTO v_connected_username
                                    FROM players
                                    WHERE player_id = v_connected_player_id;
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        v_connected_username := 'Неизвестный игрок';
                                END;

                                DBMS_OUTPUT.PUT_LINE('Игрок ' || v_connected_username || ' подключился к игре (цвет: ' || 
                                                     CASE v_connected_color WHEN 'W' THEN 'белые' ELSE 'черные' END || ').');

                                SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;

                                IF v_game.player_white_id = v_viewer_player_id THEN
                                    v_my_color := 'W';
                                ELSIF v_game.player_black_id = v_viewer_player_id THEN
                                    v_my_color := 'B';
                                END IF;
                                
                                EXIT;
                            END IF;
                            
                            BEGIN
                                EXECUTE IMMEDIATE 'BEGIN DBMS_LOCK.SLEEP(3); END;';
                            EXCEPTION
                                WHEN OTHERS THEN
                                    DECLARE
                                        v_start_time DATE := SYSDATE;
                                    BEGIN
                                        WHILE (SYSDATE - v_start_time) * 86400 < 3 LOOP
                                            NULL;
                                        END LOOP;
                                    END;
                            END;
                        END LOOP;

                        IF v_game.status IN ('O', 'C') THEN
                            DBMS_OUTPUT.PUT_LINE('Тайм-аут ожидания подключения (5 минут).');
                            RETURN;
                        END IF;

                        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
                    END;
                ELSE

                    DBMS_OUTPUT.PUT_LINE('К игре еще никто не подключился.');
                    RETURN;
                END IF;
            END IF;

            IF UPPER(p_wait_for_turn) = 'Y' AND v_game.status = 'A' AND NOT v_waited_for_connection THEN

                IF v_my_color IS NOT NULL AND v_game.current_turn = v_my_color THEN

                    NULL;
                ELSE
                    DECLARE
                        v_initial_turn CHAR(1) := v_game.current_turn;
                        v_initial_move_count NUMBER;
                    BEGIN
                    SELECT COUNT(*) INTO v_initial_move_count FROM game_moves WHERE game_id = v_target_game_id;
                    
                    v_loop_start_time := SYSDATE;
                    v_timeout_sec := NVL(v_game.time_limit_move_sec, 300); 

                    WHILE v_game.status = 'A' 
                    AND SYSDATE < v_loop_start_time + (v_timeout_sec / 86400) 
                    LOOP
                        DECLARE
                            v_current_move_count NUMBER;
                        BEGIN
                            SELECT COUNT(*) INTO v_current_move_count FROM game_moves WHERE game_id = v_target_game_id;

                            IF v_my_color IS NOT NULL THEN
                                IF v_game.current_turn = v_my_color THEN
                                    EXIT;
                                END IF;

                            ELSIF v_current_move_count > v_initial_move_count OR v_game.current_turn != v_initial_turn THEN
                                EXIT;
                            END IF;
                        END;
                        
                        BEGIN
                            EXECUTE IMMEDIATE 'BEGIN DBMS_LOCK.SLEEP(3); END;';
                        EXCEPTION
                            WHEN OTHERS THEN
                                DECLARE
                                    v_start_time DATE := SYSDATE;
                                BEGIN
                                    WHILE (SYSDATE - v_start_time) * 86400 < 3 LOOP
                                        NULL;
                                    END LOOP;
                                END;
                        END;
                        SELECT * INTO v_game FROM games WHERE game_id = v_target_game_id;
                    END LOOP;

                    IF v_my_color IS NOT NULL THEN

                        IF v_game.current_turn = v_my_color THEN
                            v_wait_message := 'ВАШ ХОД!';
                        ELSIF v_game.status != 'A' THEN
                            v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
                        ELSE 
                            v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
                        END IF;
                    ELSE

                        DECLARE
                            v_current_move_count NUMBER;
                            v_was_move_made BOOLEAN := FALSE;
                        BEGIN
                            SELECT COUNT(*) INTO v_current_move_count FROM game_moves WHERE game_id = v_target_game_id;
                            v_was_move_made := (v_current_move_count > v_initial_move_count) OR (v_game.current_turn != v_initial_turn);
                            
                            IF v_game.status != 'A' THEN
                                v_wait_message := 'Игра завершилась во время ожидания (Статус: ' || v_game.status || ').';
                            ELSIF NOT v_was_move_made AND v_game.status = 'A' THEN

                                v_wait_message := 'Тайм-аут ожидания. Ход не сделан.';
                            END IF;

                        END;
                    END IF;
                END;
                END IF;
            END IF;
        END;

        v_decoded_board := f_get_current_board_position(v_target_game_id, v_game.rule_id);

        IF v_game.status NOT IN ('A', 'O', 'C') THEN

            v_board_size := SQRT(LENGTH(v_decoded_board));
            p_init_board_map(v_board_size);

            v_printable_board := f_get_board_as_clob(v_decoded_board);
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE('ИГРА ЗАВЕРШЕНА');
            DBMS_OUTPUT.PUT_LINE('==================================================');
            DBMS_OUTPUT.PUT_LINE(v_printable_board);

            DECLARE
                v_winner_id players.player_id%TYPE;
                v_loser_id  players.player_id%TYPE;
                v_winner_name players.username%TYPE;
                v_loser_name  players.username%TYPE;
            BEGIN
                IF v_game.status = 'D' THEN
                    DBMS_OUTPUT.PUT_LINE('Результат: Ничья.');
                ELSIF v_game.status = 'T' THEN
                    DBMS_OUTPUT.PUT_LINE('Результат: Игра завершена по таймауту.');
                    IF v_game.winner_player_color IS NOT NULL THEN
                        IF v_game.winner_player_color = 'W' THEN
                            v_winner_id := v_game.player_white_id;
                            v_loser_id  := v_game.player_black_id;
                        ELSE
                            v_winner_id := v_game.player_black_id;
                            v_loser_id  := v_game.player_white_id;
                        END IF;
                        
                        BEGIN 
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_winner_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        BEGIN 
                            SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_loser_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        
                        DBMS_OUTPUT.PUT_LINE('Победитель: ' || v_winner_name || ' | Проигравший: ' || v_loser_name);
                    END IF;
                ELSIF v_game.status IN ('V', 'R') THEN
                    IF v_game.winner_player_color IS NOT NULL THEN
                        IF v_game.winner_player_color = 'W' THEN
                            v_winner_id := v_game.player_white_id;
                            v_loser_id  := v_game.player_black_id;
                        ELSE
                            v_winner_id := v_game.player_black_id;
                            v_loser_id  := v_game.player_white_id;
                        END IF;
                        
                        BEGIN 
                            SELECT username INTO v_winner_name FROM players WHERE player_id = v_winner_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_winner_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        BEGIN 
                            SELECT username INTO v_loser_name FROM players WHERE player_id = v_loser_id; 
                        EXCEPTION 
                            WHEN NO_DATA_FOUND THEN 
                                v_loser_name := 'AI (difficulty_level: ' || NVL(v_game.ai_difficulty, 'N') || ')'; 
                        END;
                        
                        IF v_game.status = 'R' THEN
                            DBMS_OUTPUT.PUT_LINE('Результат: ' || v_loser_name || ' сдался. Победитель: ' || v_winner_name || '.');
                        ELSE
                            DBMS_OUTPUT.PUT_LINE('Результат: Победа игрока ' || v_winner_name || ' над ' || v_loser_name || '.');
                        END IF;
                    END IF;
                END IF;
            END;

            IF v_game.match_id IS NOT NULL THEN
                DECLARE
                    v_match matches%ROWTYPE;
                    v_game_count NUMBER;
                    v_game_number NUMBER;
                    v_match_status CHAR(1);
                    v_next_game_id NUMBER;
                    v_is_viewer_winner BOOLEAN := FALSE;
                BEGIN
                    BEGIN
                        SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;
                        SELECT status INTO v_match_status FROM matches WHERE match_id = v_game.match_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            NULL;
                    END;

                    IF v_match.match_id IS NOT NULL THEN
                        SELECT COUNT(*) INTO v_game_count
                        FROM games
                        WHERE match_id = v_game.match_id;

                        SELECT COUNT(*) INTO v_game_number
                        FROM games
                        WHERE match_id = v_game.match_id
                          AND game_id <= v_target_game_id;

                        IF v_game.winner_player_color IS NOT NULL THEN
                            IF (v_game.winner_player_color = 'W' AND v_game.player_white_id = v_viewer_player_id) OR
                               (v_game.winner_player_color = 'B' AND v_game.player_black_id = v_viewer_player_id) THEN
                                v_is_viewer_winner := TRUE;
                            END IF;
                        END IF;

                        IF v_match_status = 'C' THEN
                            IF v_is_viewer_winner THEN
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                                DBMS_OUTPUT.PUT_LINE('ВЫ ПОБЕДИЛИ В МАТЧЕ!');
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                            ELSE
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                                DBMS_OUTPUT.PUT_LINE('МАТЧ ЗАВЕРШЕН');
                                DBMS_OUTPUT.PUT_LINE('==================================================');
                            END IF;
                        ELSIF v_game.status IN ('V', 'R') AND v_game.winner_player_color IS NOT NULL THEN
                            IF v_is_viewer_winner THEN
                                BEGIN
                                    SELECT game_id INTO v_next_game_id
                                    FROM games
                                    WHERE match_id = v_game.match_id
                                      AND game_id > v_target_game_id
                                      AND status = 'A'
                                    ORDER BY game_id ASC
                                    FETCH FIRST 1 ROW ONLY;
                                    
                                    DBMS_OUTPUT.PUT_LINE('==================================================');
                                    DBMS_OUTPUT.PUT_LINE('Вы победили в игре ' || v_game_number || ' матча.');
                                    DBMS_OUTPUT.PUT_LINE('Начинается игра ' || (v_game_number + 1) || '...');
                                    DBMS_OUTPUT.PUT_LINE('==================================================');
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        NULL;
                                END;
                            END IF;
                        END IF;
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        NULL;
                END;
            END IF;

            IF v_game.puzzle_id IS NULL THEN
                DBMS_OUTPUT.PUT_LINE('-- Используйте watch_game_replay(' || v_target_game_id || ') для просмотра полной партии.');
            END IF;
            
            UPDATE spectators SET left_at = SYSDATE 
            WHERE player_id = v_viewer_player_id AND game_id = v_target_game_id AND left_at IS NULL;
            COMMIT;
            
            RETURN;
        END IF;

        v_board_size := SQRT(LENGTH(v_decoded_board));
        p_init_board_map(v_board_size);

        v_active_player_id := CASE v_game.current_turn WHEN 'W' THEN v_game.player_white_id ELSE v_game.player_black_id END;

        IF v_game.status = 'A' AND v_viewer_player_id = v_active_player_id THEN
            v_legal_moves := find_all_player_moves(v_decoded_board, v_game.current_turn, v_game.rule_id);
            IF v_legal_moves.COUNT > 0 AND v_legal_moves(1).is_capture = 'Y' THEN
                FOR i IN 1 .. v_legal_moves.COUNT LOOP
                    FOR j IN 1 .. v_legal_moves(i).path.COUNT LOOP
                        v_highlight_indices(v_legal_moves(i).path(j).end_idx) := TRUE;
                    END LOOP;
                END LOOP;
            END IF;
        END IF;
        
        IF v_wait_message IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('---');
            DBMS_OUTPUT.PUT_LINE(v_wait_message);
        END IF;

        IF v_game.status = 'A' THEN
            DECLARE
                v_white_player_name players.username%TYPE;
                v_black_player_name players.username%TYPE;
                v_players_info VARCHAR2(500) := '';
                v_ai_difficulty_to_show CHAR(1);
            BEGIN

                IF v_game.puzzle_id IS NOT NULL THEN
                    BEGIN
                        SELECT difficulty_level INTO v_ai_difficulty_to_show
                        FROM puzzles
                        WHERE puzzle_id = v_game.puzzle_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_ai_difficulty_to_show := v_game.ai_difficulty;
                    END;
                ELSE
                    v_ai_difficulty_to_show := v_game.ai_difficulty;
                END IF;
                
                IF v_game.player_white_id IS NOT NULL THEN
                    BEGIN
                        SELECT username INTO v_white_player_name FROM players WHERE player_id = v_game.player_white_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_white_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                    END;
                ELSE
                    v_white_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                END IF;
                
                IF v_game.player_black_id IS NOT NULL THEN
                    BEGIN
                        SELECT username INTO v_black_player_name FROM players WHERE player_id = v_game.player_black_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_black_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                    END;
                ELSE
                    v_black_player_name := 'AI (difficulty_level: ' || NVL(v_ai_difficulty_to_show, 'N') || ')';
                END IF;
                
                v_players_info := 'Белые: ' || v_white_player_name || ' | Черные: ' || v_black_player_name;
                DBMS_OUTPUT.PUT_LINE(v_players_info);

                IF v_game.match_id IS NOT NULL THEN
                    DECLARE
                        v_match matches%ROWTYPE;
                        v_player1_id players.player_id%TYPE;
                        v_player2_id players.player_id%TYPE;
                        v_player1_wins NUMBER := 0;
                        v_player2_wins NUMBER := 0;
                        v_player1_name players.username%TYPE;
                        v_player2_name players.username%TYPE;
                        v_match_info VARCHAR2(500);
                    BEGIN
                        SELECT * INTO v_match FROM matches WHERE match_id = v_game.match_id;

                        BEGIN
                            SELECT player_white_id, player_black_id
                            INTO v_player1_id, v_player2_id
                            FROM (
                                SELECT player_white_id, player_black_id
                                FROM games
                                WHERE match_id = v_game.match_id
                                ORDER BY game_id ASC
                            )
                            WHERE ROWNUM = 1;
                        EXCEPTION
                            WHEN NO_DATA_FOUND THEN
                                NULL;
                        END;

                        IF v_player1_id IS NOT NULL AND v_player2_id IS NOT NULL THEN
                            FOR r IN (
                                SELECT winner_player_color, status
                                FROM games
                                WHERE match_id = v_game.match_id
                                  AND status IN ('V', 'D', 'T', 'R')
                            ) LOOP
                                IF r.status IN ('V', 'R') THEN
                                    IF r.winner_player_color = 'W' THEN
                                        v_player1_wins := v_player1_wins + 1;
                                    ELSIF r.winner_player_color = 'B' THEN
                                        v_player2_wins := v_player2_wins + 1;
                                    END IF;
                                END IF;
                            END LOOP;

                            BEGIN
                                SELECT username INTO v_player1_name FROM players WHERE player_id = v_player1_id;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_player1_name := 'Игрок 1';
                            END;
                            
                            BEGIN
                                SELECT username INTO v_player2_name FROM players WHERE player_id = v_player2_id;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    v_player2_name := 'Игрок 2';
                            END;

                            v_match_info := 'Матч (ID: ' || v_game.match_id || ', Best of ' || v_match.games_to_win || 
                                          ') | Игра ID: ' || v_target_game_id ||
                                          ' | Счет: ' || v_player1_name || ' ' || v_player1_wins || ':' || v_player2_wins || ' ' || v_player2_name ||
                                          ' | Нужно для победы: ' || (TRUNC(v_match.games_to_win / 2) + 1) || ' игры';
                            
                            DBMS_OUTPUT.PUT_LINE(v_match_info);
                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            NULL;
                    END;
                END IF;
            END;
            SELECT COUNT(*) INTO v_move_count FROM game_moves WHERE game_id = v_target_game_id;
            IF v_active_player_id IS NOT NULL THEN
                SELECT p.username INTO v_player_username FROM players p WHERE p.player_id = v_active_player_id;
            END IF;

            IF v_game.puzzle_id IS NOT NULL THEN
                DECLARE
                    v_puzzle_difficulty CHAR(1);
                BEGIN
                    SELECT difficulty_level INTO v_puzzle_difficulty
                    FROM puzzles
                    WHERE puzzle_id = v_game.puzzle_id;
                    
                    v_status_header := 'Задача №' || v_game.puzzle_id || ' (Сложность: ' || 
                                      CASE v_puzzle_difficulty WHEN 'E' THEN 'Легкая' WHEN 'M' THEN 'Средняя' WHEN 'H' THEN 'Высокая' ELSE v_puzzle_difficulty END || 
                                      ') | Ход(#' || (v_move_count + 1) || ') игрока: ' || 
                                      NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
                END;
            ELSE
                v_status_header := 'Ход(#' || (v_move_count + 1) || ') игрока: ' || NVL(v_player_username, 'AI (Server)') || ' (' || v_game.current_turn || ')';
            END IF;

            IF v_game.draw_offer_status = 'O' AND v_game.draw_offered_by_color IS NOT NULL THEN
                IF v_my_color IS NOT NULL AND v_game.draw_offered_by_color != v_my_color THEN
                    v_status_header := v_status_header || ' | ВАМ ПРЕДЛОЖЕНА НИЧЬЯ (примите: A)';
                ELSIF v_my_color IS NOT NULL AND v_game.draw_offered_by_color = v_my_color THEN
                    v_status_header := v_status_header || ' | Вы предложили ничью (ожидайте ответа)';
                ELSE
                    v_status_header := v_status_header || ' | Предложение ничьей от ' || CASE v_game.draw_offered_by_color WHEN 'W' THEN 'белых' ELSE 'черных' END;
                END IF;
            END IF;

            DECLARE
                v_time_info VARCHAR2(500) := '';
                v_current_time DATE := SYSDATE;
                v_last_move_time DATE;
                v_move_elapsed_sec NUMBER;
                v_move_remaining_sec NUMBER;
                v_move_end_time DATE;
                v_white_time_remaining NUMBER;
                v_black_time_remaining NUMBER;
                v_white_end_time DATE;
                v_black_end_time DATE;
            BEGIN

                IF v_game.time_limit_game_sec IS NOT NULL AND 
                   v_game.time_white_remaining_sec IS NOT NULL AND 
                   v_game.time_black_remaining_sec IS NOT NULL THEN

                    BEGIN
                        SELECT MAX(move_timestamp) INTO v_last_move_time
                        FROM game_moves
                        WHERE game_id = v_target_game_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            v_last_move_time := v_game.start_time;
                    END;

                    IF v_game.current_turn = 'W' THEN
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_white_time_remaining := GREATEST(0, v_game.time_white_remaining_sec - v_move_elapsed_sec);
                        v_black_time_remaining := v_game.time_black_remaining_sec;
                    ELSE
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_white_time_remaining := v_game.time_white_remaining_sec;
                        v_black_time_remaining := GREATEST(0, v_game.time_black_remaining_sec - v_move_elapsed_sec);
                    END IF;

                    v_white_end_time := v_current_time + (v_white_time_remaining / 86400);
                    v_black_end_time := v_current_time + (v_black_time_remaining / 86400);

                    DBMS_OUTPUT.PUT_LINE('Время белых: осталось ' || 
                                       ROUND(v_white_time_remaining) || ' сек (закончится ' || 
                                       TO_CHAR(v_white_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);

                    DBMS_OUTPUT.PUT_LINE('Время черных: осталось ' || 
                                       ROUND(v_black_time_remaining) || ' сек (закончится ' || 
                                       TO_CHAR(v_black_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);
                END IF;

                IF v_game.time_limit_move_sec IS NOT NULL AND v_game.time_limit_game_sec IS NULL THEN
                    BEGIN
                        SELECT MAX(move_timestamp) INTO v_last_move_time
                        FROM game_moves
                        WHERE game_id = v_target_game_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            IF v_game.status = 'A' THEN
                                v_last_move_time := v_game.start_time;
                            ELSE
                                v_last_move_time := NULL;
                            END IF;
                    END;
                    
                    IF v_last_move_time IS NOT NULL AND v_game.status = 'A' THEN
                        v_move_elapsed_sec := (v_current_time - v_last_move_time) * 86400;
                        v_move_remaining_sec := GREATEST(0, v_game.time_limit_move_sec - v_move_elapsed_sec);
                        v_move_end_time := v_last_move_time + (v_game.time_limit_move_sec / 86400);
                        
                        DBMS_OUTPUT.PUT_LINE('Время на ход: осталось ' || 
                                          ROUND(v_move_remaining_sec) || ' сек (закончится ' || 
                                          TO_CHAR(v_move_end_time, 'DD.MM.YYYY HH24:MI:SS') || ')' || c_nl);
                    END IF;
                END IF;
            END;
        END IF;

        IF v_game.status = 'A' THEN
            DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
        ELSIF v_game.status != 'O' THEN

            v_status_header := 'Состояние доски: ' || v_game.status || '. Ожидание игрока.';
            DBMS_OUTPUT.PUT_LINE(v_status_header || c_nl);
        END IF;

        v_printable_board := f_get_board_as_clob(v_decoded_board, v_highlight_indices);
        DBMS_OUTPUT.PUT_LINE(v_printable_board);
    END;
END print_active_board;

PROCEDURE make_move(p_move_notation IN VARCHAR2) IS
    v_game_id   NUMBER;
    v_game      games%ROWTYPE;
    v_player_id players.player_id%TYPE;
    v_human_msg VARCHAR2(2000);
    v_ai_msg    VARCHAR2(2000);
    v_error_msg VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    v_game_id   := get_active_game(v_player_id);
    
    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id; 
    
    IF v_game_id IS NULL THEN
        v_error_msg := 'Нет активных игр, чтобы сделать ход.';
        p_audit_log(v_player_id, NULL, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status != 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') еще не активна. Противник не подключился.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF (v_game.current_turn = 'W' AND v_game.player_white_id != v_player_id) OR 
       (v_game.current_turn = 'B' AND v_game.player_black_id != v_player_id) 
    THEN
        v_error_msg := 'Сейчас не ваш ход. (ID Игры: ' || v_game_id || ', Очередь: ' || v_game.current_turn || ').';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    p_process_move(v_game_id, TRIM(p_move_notation), v_player_id, v_human_msg);

    IF INSTR(LOWER(v_human_msg), 'неверный ход') > 0 OR INSTR(LOWER(v_human_msg), 'нелегальный ход') > 0 THEN
        RETURN;
    END IF;

    IF v_human_msg IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(v_human_msg);
    END IF;

    SELECT status INTO v_game.status FROM games WHERE game_id = v_game_id;

    print_active_board(p_game_id => v_game_id);

    DECLARE
        v_next_game_state games%ROWTYPE;
        v_ai_move         VARCHAR2(50);
        v_ai_board_pos    VARCHAR2(100);
    BEGIN
        SELECT * INTO v_next_game_state FROM games WHERE game_id = v_game_id;

        IF v_next_game_state.status = 'A' AND v_next_game_state.ai_difficulty IS NOT NULL AND
           ((v_next_game_state.current_turn = 'W' AND v_next_game_state.player_white_id IS NULL) OR
            (v_next_game_state.current_turn = 'B' AND v_next_game_state.player_black_id IS NULL))
        THEN

            v_ai_board_pos := f_get_current_board_position(v_game_id, v_next_game_state.rule_id);

            IF INSTR(v_ai_board_pos, c_empty_field) > 0 THEN
                v_ai_board_pos := encode_board(v_ai_board_pos);
            END IF;

            DECLARE
                v_ai_difficulty CHAR(1) := v_next_game_state.ai_difficulty;
            BEGIN
                v_ai_move := get_ai_move(
                    p_board_position => v_ai_board_pos, 
                    p_ai_color       => v_next_game_state.current_turn, 
                    p_rule_id        => v_next_game_state.rule_id, 
                    p_difficulty     => v_ai_difficulty
                );
            END;

            IF v_ai_move IS NOT NULL THEN
                p_process_move(v_game_id, v_ai_move, NULL, v_ai_msg);
                DBMS_OUTPUT.PUT_LINE(c_nl || v_ai_msg);
                
                print_active_board(p_game_id => v_game_id);
            END IF;
        END IF;
    END;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END make_move;

PROCEDURE cancel_game IS
    v_game_id   NUMBER;
    v_player_id players.player_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(user);

    DECLARE
        v_spectating_game_id NUMBER := NULL;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя отменить игру.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    UPDATE players SET last_activity_at = SYSDATE WHERE player_id = v_player_id;
    v_game_id := get_active_game(v_player_id);
    
    IF v_game_id IS NULL THEN
        v_error_msg := 'Нет активных игр или вызовов для отмены.';
        p_audit_log(v_player_id, NULL, v_error_msg); 
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
  
    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Эту игру (ID: ' || v_game_id || ') нельзя отменить (статус '||v_game.status||'). Используйте resign_game, чтобы сдаться.';
        p_audit_log(v_player_id, v_game_id, v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.match_id IS NOT NULL THEN
        DELETE FROM matches WHERE match_id = v_game.match_id;
        p_audit_log(v_player_id, v_game_id, 'MATCH_CANCEL');
        DBMS_OUTPUT.PUT_LINE('Связанный вызов на матч (ID: ' || v_game.match_id || ') также отменен.');
    END IF;
            
    DELETE FROM games WHERE game_id = v_game_id;
    p_audit_log(v_player_id, v_game_id, 'CANCEL_GAME');
    DBMS_OUTPUT.PUT_LINE('Ваш вызов/открытая игра (ID: ' || v_game_id || ') был(а) отменен(а).');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        v_error_msg := 'Неожиданная ошибка при отмене игры: ' || SQLERRM;
        p_audit_log(v_player_id, v_game_id, SUBSTR(v_error_msg, 1, 2000));
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
END cancel_game;

PROCEDURE draw(p_action IN CHAR) IS
    v_player_id players.player_id%TYPE;
    v_game_id   games.game_id%TYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(2000);
    v_my_color  CHAR(1);
    v_action    CHAR(1) := UPPER(p_action);
BEGIN
    v_player_id := get_or_create_player_id(USER);

    DECLARE
        v_spectating_game_id NUMBER := NULL;
    BEGIN
        BEGIN
            SELECT game_id INTO v_spectating_game_id
            FROM spectators
            WHERE player_id = v_player_id
              AND left_at IS NULL
              AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
        
        IF v_spectating_game_id IS NOT NULL THEN
            v_error_msg := 'Вы находитесь в режиме просмотра (Игра ID: ' || v_spectating_game_id || '). Нельзя управлять ничьей.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            DBMS_OUTPUT.PUT_LINE('--[ Вызовите game_logic.stop_spectating; чтобы выйти из режима просмотра ]--');
            RETURN;
        END IF;
    END;

    v_game_id := get_active_game(v_player_id);
    IF v_game_id IS NULL THEN
        v_error_msg := 'У вас нет активной игры.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    SELECT * INTO v_game FROM games WHERE game_id = v_game_id FOR UPDATE;

    IF v_game.status != 'A' THEN
        v_error_msg := 'Игра (ID: ' || v_game_id || ') неактивна (статус: ' || v_game.status || ').';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.ai_difficulty IS NOT NULL OR v_game.puzzle_id IS NOT NULL THEN
        v_error_msg := 'Предложение ничьей недоступно в играх против ИИ и в задачах.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    IF v_game.player_white_id = v_player_id THEN
        v_my_color := 'W';
    ELSE
        v_my_color := 'B';
    END IF;

    IF v_action = 'O' THEN
        IF v_game.draw_offer_status = 'O' THEN
            IF v_game.draw_offered_by_color = v_my_color THEN
                v_error_msg := 'Вы уже предложили ничью.';
                p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK;
                RETURN;
            ELSE

                p_finish_game(
                    p_game_id      => v_game_id,
                    p_status       => 'D',
                    p_audit_event  => 'DRAW_ACCEPT',
                    p_player_id    => v_player_id
                );
                UPDATE games
                SET draw_offer_status = 'S'
                WHERE game_id = v_game_id;
                DBMS_OUTPUT.PUT_LINE('Ничья по соглашению сторон (оба игрока предложили ничью).');
                RETURN;
            END IF;
        END IF;

        UPDATE games
        SET draw_offer_status     = 'O',
            draw_offered_by_color = v_my_color,
            draw_offered_at       = SYSDATE
        WHERE game_id = v_game_id;
        
        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_OFFER');
        DBMS_OUTPUT.PUT_LINE('Вы предложили ничью. Ожидайте ответа оппонента.');

    ELSIF v_action = 'A' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его принять.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;
        
        IF v_game.draw_offered_by_color = v_my_color THEN
            v_error_msg := 'Нельзя принять собственное предложение о ничьей.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        p_finish_game(
            p_game_id      => v_game_id,
            p_status       => 'D',
            p_audit_event  => 'DRAW_ACCEPT',
            p_player_id    => v_player_id
        );

        UPDATE games
        SET draw_offer_status = 'S'
        WHERE game_id = v_game_id; 
        DBMS_OUTPUT.PUT_LINE('Ничья по соглашению сторон.');

    ELSIF v_action = 'C' THEN
        IF v_game.draw_offer_status IS NULL OR v_game.draw_offer_status != 'O' THEN
            v_error_msg := 'Нет активного предложения о ничьей, чтобы его отменить.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        IF v_game.draw_offered_by_color != v_my_color THEN
            v_error_msg := 'Нельзя отменить предложение оппонента. Можно только отозвать свое предложение.';
            p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
        END IF;

        UPDATE games
        SET draw_offer_status     = NULL, 
            draw_offered_by_color = NULL,
            draw_offered_at       = NULL
        WHERE game_id = v_game_id;

        p_audit_log(v_player_id, v_game_id, p_event_msg => 'DRAW_CANCEL');
        DBMS_OUTPUT.PUT_LINE('Вы отменили свое предложение о ничьей.');

    ELSE
        v_error_msg := 'Неверный p_action: "' || p_action || '". Допустимые значения: O, A, C.';
        p_audit_log(v_player_id, v_game_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END draw;

PROCEDURE create_match(
    p_opponent_username   IN VARCHAR2 DEFAULT NULL,
    p_games_to_win        IN NUMBER   DEFAULT 3,
    p_player_color        IN CHAR     DEFAULT NULL,
    p_rule_id             IN NUMBER   DEFAULT 1,
    p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
    p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
    p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
    p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'
) IS
    v_current_player_id  players.player_id%TYPE;
    v_error_msg          VARCHAR2(2000);
    v_status_message     VARCHAR2(2000);
    
    v_game_id            games.game_id%TYPE;
    v_match_id           matches.match_id%TYPE;
    v_games_to_win       NUMBER;
    
BEGIN
    v_current_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_current_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_current_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    v_games_to_win := NVL(p_games_to_win, 3);
    
    IF v_games_to_win <= 0 OR MOD(v_games_to_win, 2) = 0 THEN
        v_error_msg := 'Неверное количество игр для победы (p_games_to_win). Должно быть нечетным числом (best of N, где N нечетное).';
        p_audit_log(v_current_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    create_game(
        p_opponent_username   => p_opponent_username,
        p_ai_difficulty       => NULL,
        p_player_color        => p_player_color,
        p_rule_id             => p_rule_id,
        p_time_limit_move_sec => p_time_limit_move_sec,
        p_time_limit_game_sec => p_time_limit_game_sec,
        p_draw_moves_limit    => p_draw_moves_limit,
        p_enable_pos_rep_draw => p_enable_pos_rep_draw,
        p_puzzle_id           => NULL,
        p_daily               => 'N'
    );
    
    v_game_id := get_active_game(v_current_player_id);

    IF v_game_id IS NULL THEN
        RETURN;
    END IF;

    DECLARE
        v_fetched_rule_id games.rule_id%TYPE;
        v_fetched_status  games.status%TYPE;
    BEGIN
        SELECT rule_id, status 
        INTO v_fetched_rule_id, v_fetched_status
        FROM games 
        WHERE game_id = v_game_id;

        INSERT INTO matches (
            rule_id, 
            games_to_win, 
            status
        )
        VALUES (
            v_fetched_rule_id,
            v_games_to_win,
            v_fetched_status
        )
        RETURNING match_id INTO v_match_id;
    END;

    UPDATE games
    SET match_id = v_match_id
    WHERE game_id = v_game_id;
    
    IF p_opponent_username IS NOT NULL THEN
        v_status_message := 'Вызов на матч (ID: ' || v_match_id || ') до ' || v_games_to_win || ' побед брошен игроку ' || p_opponent_username;
    ELSE
        v_status_message := 'Открытый матч (ID: ' || v_match_id || ') до ' || v_games_to_win || ' побед создан. Ожидайте оппонента.';
    END IF;

    p_audit_log(v_current_player_id, v_game_id, 'MATCH_CREATED');
    DBMS_OUTPUT.PUT_LINE(v_status_message);
    
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_audit_log(v_current_player_id, NULL, 'КРИТИЧЕСКАЯ ОШИБКА в create_match: ' || SQLERRM);
        RAISE;
END create_match;

PROCEDURE join_match(p_match_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_match     matches%ROWTYPE;
    v_game      games%ROWTYPE;
    v_error_msg VARCHAR2(2000);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        SELECT * INTO v_match 
        FROM matches 
        WHERE match_id = p_match_id 
        FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Матч с ID ' || p_match_id || ' не найден.';
            p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
    END;

    BEGIN
        SELECT * INTO v_game 
        FROM games 
        WHERE match_id = p_match_id 
          AND status IN ('O', 'C');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Не найдено ожидающей игры для этого матча (ID: ' || p_match_id || ').';
            p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
            RETURN;
    END;
    
    IF v_match.status NOT IN ('O', 'C') THEN
        v_error_msg := 'Матч (ID: ' || p_match_id || ') уже начат или завершен (Статус: ' || v_match.status || ').';
        p_audit_log(v_player_id, p_match_id, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        ROLLBACK;
        RETURN;
    END IF;

    join_game(v_game.game_id);

    DECLARE
        v_game_status CHAR(1);
    BEGIN
        SELECT status INTO v_game_status 
        FROM games 
        WHERE game_id = v_game.game_id;
        
        IF v_game_status = 'A' THEN
            UPDATE matches
            SET status = 'A'
            WHERE match_id = p_match_id;
            
            DBMS_OUTPUT.PUT_LINE('Вы присоединились к матчу (ID: ' || p_match_id || '). Начинается первая игра (ID: ' || v_game.game_id || ').');
            p_audit_log(v_player_id, v_game.game_id, 'MATCH_JOINED');
            COMMIT;
        ELSE

            ROLLBACK;
        END IF;
    END;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END join_match;

PROCEDURE create_puzzle(
    p_board_position   IN VARCHAR2,
    p_turn_to_move     IN CHAR,
    p_moves_to_solve   IN NUMBER DEFAULT NULL,
    p_difficulty_level IN CHAR DEFAULT 'M',
    p_solution          IN VARCHAR2 DEFAULT NULL
) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(2000);
    
    v_single_line_board VARCHAR2(200) := '';
    v_board_size        NUMBER;
    v_rule_id           game_rules.rule_id%TYPE;
    v_encoded_board     VARCHAR2(100);
    v_new_puzzle_id     puzzles.puzzle_id%TYPE;

BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы создать задачу.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF UPPER(p_turn_to_move) NOT IN ('W', 'B') THEN
        v_error_msg := 'Ошибка: p_turn_to_move должен быть ''W'' или ''B''.';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_moves_to_solve IS NOT NULL AND p_moves_to_solve <= 0 THEN
         v_error_msg := 'Ошибка: p_moves_to_solve должен быть больше 0 или NULL.';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    IF p_difficulty_level IS NOT NULL AND p_difficulty_level NOT IN ('E', 'M', 'H') THEN
        v_error_msg := 'Ошибка: p_difficulty_level должен быть ''E'' (Easy), ''M'' (Medium) или ''H'' (Hard).';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        -- Удаляем пробелы из RLE строки
        v_encoded_board := REGEXP_REPLACE(p_board_position, '[[:space:]]', '');
        
        -- Декодируем RLE в развернутую строку для валидации
        v_single_line_board := decode_board(v_encoded_board);
        
        IF LENGTH(v_single_line_board) > 200 THEN
            v_error_msg := 'Ошибка: Размер доски превышает допустимый предел.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        IF LENGTH(v_single_line_board) = 64 THEN
            v_board_size := 8;
        ELSIF LENGTH(v_single_line_board) = 100 THEN
            v_board_size := 10;
        ELSE
            v_error_msg := 'Ошибка: Неверный размер доски. Ожидалось 64 (8x8) или 100 (10x10) символов, получено: ' || LENGTH(v_single_line_board);
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        IF REGEXP_LIKE(v_single_line_board, '[^wWbB+]') THEN
            v_error_msg := 'Ошибка: Доска содержит недопустимые символы. Разрешены только: w, W, b, B, +.';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        
        IF INSTR(v_single_line_board, 'w') = 0 AND INSTR(v_single_line_board, 'W') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной белой фигуры (w, W).';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;
        IF INSTR(v_single_line_board, 'b') = 0 AND INSTR(v_single_line_board, 'B') = 0 THEN
            v_error_msg := 'Ошибка: На доске нет ни одной черной фигуры (b, B).';
            p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN;
        END IF;

        p_init_board_map(v_board_size);
        
        FOR i IN 1 .. LENGTH(v_single_line_board) LOOP
            DECLARE
                v_piece CHAR(1) := SUBSTR(v_single_line_board, i, 1);
                v_field rec_board_field;
            BEGIN

                IF v_piece IN ('w', 'W', 'b', 'B') THEN
                    IF NOT g_map_by_idx.EXISTS(i) THEN
                        v_error_msg := 'Ошибка: Недопустимый индекс позиции: ' || i;
                        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        RETURN;
                    END IF;
                    
                    v_field := g_map_by_idx(i);
                    
                    -- Проверка: фигура должна быть на темной клетке
                    -- В шашках темные клетки - это те, где (row + col) четное
                    IF MOD(v_field.row_num + v_field.col_num, 2) != 0 THEN
                        v_error_msg := 'Ошибка: Фигура на позиции ' || v_field.notation || 
                                     ' (индекс ' || i || ', строка ' || v_field.row_num || ', столбец ' || v_field.col_num || 
                                     ') находится на светлой клетке. В шашках фигуры могут быть только на темных клетках.';
                        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
                        DBMS_OUTPUT.PUT_LINE(v_error_msg);
                        RETURN;
                    END IF;
                END IF;
            END;
        END LOOP;

        SELECT rule_id INTO v_rule_id
        FROM game_rules
        WHERE board_size = v_board_size
        AND ROWNUM = 1;

        -- v_encoded_board уже содержит RLE формат, сохраняем как есть
        
        INSERT INTO puzzles (
            board_position,
            rule_id,
            turn_to_move,
            moves_to_solve,
            difficulty_level,
            created_by_player_id,
            solution
        ) VALUES (
            v_encoded_board,
            v_rule_id,
            UPPER(p_turn_to_move),
            p_moves_to_solve,
            p_difficulty_level,
            v_player_id,
            p_solution
        )
        RETURNING puzzle_id INTO v_new_puzzle_id;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Задача успешно создана (ID: ' || v_new_puzzle_id || ').');
        p_audit_log(v_player_id, NULL, 'PUZZLE_CREATED');

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF v_error_msg IS NULL THEN
               v_error_msg := 'Неизвестная ошибка: ' || SQLERRM;
            END IF;
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 2000));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;

END create_puzzle;

PROCEDURE show_puzzles(
    p_difficulty IN CHAR DEFAULT NULL, 
    p_puzzle_id  IN NUMBER DEFAULT NULL,
    p_solution   IN CHAR DEFAULT 'N'
) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_header    VARCHAR2(200);
    v_goal_str  VARCHAR2(50);
    v_visual_board CLOB;
    v_has_attempts BOOLEAN := FALSE;
    v_puzzle_solution VARCHAR2(1000);
    
    CURSOR c_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            pl.username AS creator_username,
            puz.board_position,
            puz.turn_to_move,
            puz.end_board_state,
            puz.solution
        FROM puzzles puz, players pl
        WHERE puz.created_by_player_id = pl.player_id(+)
          AND ((p_puzzle_id IS NOT NULL AND puz.puzzle_id = p_puzzle_id)
               OR 
               (p_puzzle_id IS NULL AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty)))
        ORDER BY puz.puzzle_id;
BEGIN
    v_player_id := get_or_create_player_id(USER);

    IF p_difficulty IS NOT NULL AND p_difficulty NOT IN ('E', 'M', 'H') THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: Сложность должна быть ''E'' (Easy), ''M'' (Medium) или ''H'' (Hard).');
        RETURN;
    END IF;

    IF p_puzzle_id IS NOT NULL THEN
        DECLARE
            r c_puzzles%ROWTYPE;
        BEGIN
            OPEN c_puzzles;
            FETCH c_puzzles INTO r;
            IF c_puzzles%FOUND THEN
                v_goal_str := CASE WHEN r.end_board_state IS NULL THEN 'Победа' ELSE 'Ничья' END;

                DECLARE
                    v_attempt_count NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_attempt_count
                    FROM games
                    WHERE puzzle_id = r.puzzle_id
                      AND (player_white_id = v_player_id OR player_black_id = v_player_id);
                    
                    v_has_attempts := (v_attempt_count > 0);
                END;
                
                DBMS_OUTPUT.PUT_LINE('==================================================');
                DBMS_OUTPUT.PUT_LINE('ЗАДАЧА ID: ' || r.puzzle_id);
                IF r.creator_username IS NOT NULL THEN
                    DBMS_OUTPUT.PUT_LINE('Автор:     ' || r.creator_username);
                END IF;
                DBMS_OUTPUT.PUT_LINE('Сложность: ' || r.difficulty_level);
                DBMS_OUTPUT.PUT_LINE('Цель:      ' || v_goal_str || ' на ходе: ' || NVL(TO_CHAR(r.moves_to_solve), '?'));
                DBMS_OUTPUT.PUT_LINE('Ваш ход:   ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);
                DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
                
                v_visual_board := f_get_board_as_clob(r.board_position);
                DBMS_OUTPUT.PUT_LINE(v_visual_board);

                IF p_solution = 'Y' THEN
                    IF v_has_attempts THEN
                        IF r.solution IS NOT NULL THEN
                            DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
                            DBMS_OUTPUT.PUT_LINE('РЕШЕНИЕ: ' || r.solution);
                        ELSE
                            DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
                            DBMS_OUTPUT.PUT_LINE('РЕШЕНИЕ: не указано');
                        END IF;
                    ELSE
                        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');
                        DBMS_OUTPUT.PUT_LINE('Нельзя смотреть решение, если не было попыток решить задачу.');
                    END IF;
                END IF;
                
                DBMS_OUTPUT.PUT_LINE('==================================================');
            ELSE
                DBMS_OUTPUT.PUT_LINE('Задача с ID ' || p_puzzle_id || ' не найдена.');
            END IF;
            CLOSE c_puzzles;
        END;
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('--- Список Доступных Задач ---');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE(' (Фильтр по Сложности: ' || p_difficulty || ')');
    ELSE
        DBMS_OUTPUT.PUT_LINE(' (Все задачи)');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 4) || 
        RPAD('Слож.', 6) || 
        RPAD('Ходов', 7) || 
        RPAD('Цель', 8) || 
        RPAD('Ход', 5) || 
        'Позиция (RLE)'
    );
    DBMS_OUTPUT.PUT_LINE(
        RPAD('-', 3, '-') || ' ' || 
        RPAD('-', 5, '-') || ' ' || 
        RPAD('-', 6, '-') || ' ' || 
        RPAD('-', 7, '-') || ' ' || 
        RPAD('-', 4, '-') || ' ' || 
        RPAD('-', 25, '-')
    );

    FOR r IN c_puzzles LOOP
        v_found := TRUE;
        v_goal_str := CASE WHEN r.end_board_state IS NULL THEN 'Победа' ELSE 'Ничья' END;
        
        DBMS_OUTPUT.PUT_LINE(
            RPAD(TO_CHAR(r.puzzle_id), 3) || ' ' || 
            RPAD(r.difficulty_level, 5) || ' ' || 
            RPAD(NVL(TO_CHAR(r.moves_to_solve), '?'), 6) || ' ' || 
            RPAD(SUBSTR(v_goal_str, 1, 6), 7) || ' ' ||
            RPAD(r.turn_to_move, 4) || ' ' || 
            r.board_position
        );
    END LOOP;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при показе задач: ' || SQLERRM);
END show_puzzles;

PROCEDURE show_my_puzzles(p_difficulty IN CHAR DEFAULT NULL) IS
    v_player_id players.player_id%TYPE;
    v_found     BOOLEAN := FALSE;
    v_visual_board CLOB;
    v_goal_str  VARCHAR2(50);
    
    CURSOR c_my_puzzles IS
        SELECT 
            puz.puzzle_id,
            puz.difficulty_level,
            puz.moves_to_solve,
            puz.board_position,
            puz.turn_to_move,
            puz.end_board_state
        FROM puzzles puz
        WHERE 
            puz.created_by_player_id = v_player_id
            AND (p_difficulty IS NULL OR puz.difficulty_level = p_difficulty)
        ORDER BY puz.puzzle_id DESC;
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    DBMS_OUTPUT.PUT_LINE('==================================================');
    DBMS_OUTPUT.PUT_LINE('              МОИ СОЗДАННЫЕ ЗАДАЧИ');
    IF p_difficulty IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('           (Фильтр по Сложности: ' || p_difficulty || ')');
    END IF;
    DBMS_OUTPUT.PUT_LINE('==================================================');

    FOR r IN c_my_puzzles LOOP
        v_found := TRUE;
        
        v_goal_str := CASE WHEN r.end_board_state IS NULL THEN 'Победа' ELSE 'Ничья' END;

        DBMS_OUTPUT.PUT_LINE('ID: ' || r.puzzle_id || ' | Сложность: ' || r.difficulty_level || ' | Цель: ' || v_goal_str || ' за ' || NVL(TO_CHAR(r.moves_to_solve), '?') || ' ход(ов)');
        DBMS_OUTPUT.PUT_LINE('Первый ход: ' || CASE r.turn_to_move WHEN 'W' THEN 'Белые' ELSE 'Черные' END);

        v_visual_board := f_get_board_as_clob(r.board_position);
        DBMS_OUTPUT.PUT_LINE(v_visual_board);
        DBMS_OUTPUT.PUT_LINE('__________________________________________________');
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;
    
    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('... У вас нет созданных задач' || 
            CASE WHEN p_difficulty IS NOT NULL THEN ' с заданной сложностью' ELSE '' END || '. ...');
    END IF;
END show_my_puzzles;

PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(2000);
    v_deleted_count NUMBER;
BEGIN
    IF p_puzzle_id IS NULL THEN
        v_error_msg := 'Ошибка: Параметр p_puzzle_id обязателен. Используйте 0 для удаления всех своих задач.';
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;
    
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы удалить задачу.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        IF p_puzzle_id = 0 THEN

            DELETE FROM puzzles
            WHERE created_by_player_id = v_player_id;
            v_deleted_count := SQL%ROWCOUNT;
            
            IF v_deleted_count = 0 THEN
                v_error_msg := 'У вас нет созданных задач для удаления.';
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK;
            ELSE
                DBMS_OUTPUT.PUT_LINE('Успешно удалено задач: ' || v_deleted_count || '.');
                p_audit_log(v_player_id, NULL, p_event_msg => 'PUZZLES_DELETED_ALL');
                COMMIT;
            END IF;
        ELSE

            DELETE FROM puzzles
            WHERE puzzle_id = p_puzzle_id
              AND created_by_player_id = v_player_id;
              
            IF SQL%ROWCOUNT = 0 THEN
                v_error_msg := 'Ошибка: Задача с ID ' || p_puzzle_id || ' не существует или не принадлежит вам.';
                DBMS_OUTPUT.PUT_LINE(v_error_msg);
                ROLLBACK;
            ELSE
                DBMS_OUTPUT.PUT_LINE('Задача (ID: ' || p_puzzle_id || ') успешно удалена.');
                p_audit_log(v_player_id, NULL, p_event_msg => 'PUZZLE_DELETED');
                COMMIT;
            END IF;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_error_msg := 'Ошибка при удалении: ' || SQLERRM;
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 2000));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;
END delete_my_puzzle;

PROCEDURE show_daily_puzzle IS
    v_today       DATE := TRUNC(SYSDATE);
    v_player_id   players.player_id%TYPE;

    v_puzzle_id      puzzles.puzzle_id%TYPE;
    v_difficulty     puzzles.difficulty_level%TYPE;
    v_moves_solve    puzzles.moves_to_solve%TYPE;
    v_turn           puzzles.turn_to_move%TYPE;
    v_board_pos      puzzles.board_position%TYPE;
    v_end_board_state puzzles.end_board_state%TYPE;
    v_author         players.username%TYPE;
    
    v_visual_board   CLOB;
    v_goal_str       VARCHAR2(100);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    BEGIN
        SELECT 
            p.puzzle_id,
            p.difficulty_level,
            p.moves_to_solve,
            p.turn_to_move,
            p.board_position,
            p.end_board_state,
            pl.username
        INTO 
            v_puzzle_id, v_difficulty, v_moves_solve, v_turn, v_board_pos, v_end_board_state, v_author
        FROM daily_puzzles dp
        JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
        LEFT JOIN players pl ON p.created_by_player_id = pl.player_id
        WHERE dp.puzzle_date = v_today;
        
        v_goal_str := CASE WHEN v_end_board_state IS NULL THEN 'Победа' ELSE 'Ничья' END;

        DBMS_OUTPUT.PUT_LINE('==================================================');
        DBMS_OUTPUT.PUT_LINE('          ЗАДАЧА ДНЯ (' || TO_CHAR(v_today, 'DD.MM.YYYY') || ')');
        DBMS_OUTPUT.PUT_LINE('==================================================');
        DBMS_OUTPUT.PUT_LINE('ID:        ' || v_puzzle_id);
        IF v_author IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('Автор:     ' || v_author);
        END IF;
        DBMS_OUTPUT.PUT_LINE('Сложность: ' || v_difficulty);
        DBMS_OUTPUT.PUT_LINE('Задача:    ' || v_goal_str || ' за ' || NVL(TO_CHAR(v_moves_solve), 'N/A') || ' ход(ов)');
        DBMS_OUTPUT.PUT_LINE('Ваш ход:   ' || CASE v_turn WHEN 'W' THEN 'Белые (W)' ELSE 'Черные (B)' END);
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');

        v_visual_board := f_get_board_as_clob(v_board_pos);
        DBMS_OUTPUT.PUT_LINE(v_visual_board);
        
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------');

        DBMS_OUTPUT.PUT_LINE('Для решения: BEGIN game_logic.create_game(p_daily => ''Y''); END;');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка: Задача на ' || TO_CHAR(v_today, 'DD.MM.YYYY') || ' еще не назначена.');
            p_audit_log(NULL, NULL, p_event_msg => 'DAILY_PUZZLE_NOT_FOUND');
    END;
END show_daily_puzzle;

PROCEDURE info(p_query IN VARCHAR2 DEFAULT NULL) IS
    v_query VARCHAR2(30) := UPPER(TRIM(p_query));
    v_show_all BOOLEAN := (v_query IS NULL OR v_query = 'ALL');
    v_show_full BOOLEAN := (v_query = 'ALL');
    v_found BOOLEAN := FALSE;
BEGIN

    IF v_query IS NULL OR v_query = '' THEN
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('           Добро пожаловать в "Шашки на Oracle"');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Для корректной работы включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('Все команды выполняются в блоках PL/SQL: BEGIN ... END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('БЫСТРЫЙ СТАРТ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('1. Включите вывод: SET SERVEROUTPUT ON;');
        DBMS_OUTPUT.PUT_LINE('2. Посмотрите справку: BEGIN game_logic.info; END;');
        DBMS_OUTPUT.PUT_LINE('3. Создайте игру против ИИ:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
        DBMS_OUTPUT.PUT_LINE('4. Посмотрите доску:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.print_active_board; END;');
        DBMS_OUTPUT.PUT_LINE('5. Сделайте ход:');
        DBMS_OUTPUT.PUT_LINE('   BEGIN game_logic.make_move(''c3-d4''); END;');
        DBMS_OUTPUT.PUT_LINE('6. ИИ автоматически ответит, и вы увидите обновленную доску.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ИСПОЛЬЗОВАНИЕ СПРАВКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Параметр p_query позволяет получить информацию по конкретной теме:');
        DBMS_OUTPUT.PUT_LINE('  - Имя процедуры (например, ''CREATE_GAME'') - информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('  - ''ALL'' - полная справка по всем процедурам и разделам');
        DBMS_OUTPUT.PUT_LINE('  - ''VIEWS'' - информация о представлениях (views) для статистики');
        DBMS_OUTPUT.PUT_LINE('  - ''RULES'' - правила игры (русские и международные шашки)');
        DBMS_OUTPUT.PUT_LINE('  - ''PARAMETERS'' - параметры игр (таймауты, ничьи)');
        DBMS_OUTPUT.PUT_LINE('  - ''STATUSES'' - статусы игр (O, C, A, V, D, T, R)');
        DBMS_OUTPUT.PUT_LINE('  - ''RATINGS'' - система рейтингов и сезонов');
        DBMS_OUTPUT.PUT_LINE('  - ''CONSTRAINTS'' - ограничения системы');
        DBMS_OUTPUT.PUT_LINE('  - ''INFO'' - информация о самой процедуре info');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''CREATE_GAME''); END;');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''ALL''); END;  -- Полная справка');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''VIEWS''); END;  -- Информация о представлениях');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''RULES''); END;  -- Правила игры');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        RETURN;
    END IF;

    IF v_query = 'INFO' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('INFO');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выводит справочную информацию о системе и процедурах.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
        DBMS_OUTPUT.PUT_LINE('  p_query - Запрос для получения информации (необязателен, по умолчанию NULL).');
        DBMS_OUTPUT.PUT_LINE('    Возможные значения:');
        DBMS_OUTPUT.PUT_LINE('      - NULL или пустая строка: краткая справка и быстрый старт');
        DBMS_OUTPUT.PUT_LINE('      - Имя процедуры: детальная информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('      - ''ALL'': полная справка по всем разделам');
        DBMS_OUTPUT.PUT_LINE('      - ''VIEWS'': информация о представлениях');
        DBMS_OUTPUT.PUT_LINE('      - ''RULES'': правила игры');
        DBMS_OUTPUT.PUT_LINE('      - ''PARAMETERS'': параметры игр');
        DBMS_OUTPUT.PUT_LINE('      - ''STATUSES'': статусы игр');
        DBMS_OUTPUT.PUT_LINE('      - ''RATINGS'': система рейтингов');
        DBMS_OUTPUT.PUT_LINE('      - ''CONSTRAINTS'': ограничения системы');
        DBMS_OUTPUT.PUT_LINE('      - ''INFO'': информация о процедуре info');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info; END;  -- Краткая справка');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''CREATE_GAME''); END;  -- Информация о процедуре');
        DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.info(p_query => ''ALL''); END;  -- Полная справка');
        RETURN;
    END IF;


    IF v_show_all OR v_query = 'CREATE_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает новую игру: PvP (против игрока), PvE (против ИИ) или Puzzle (задача).');
        IF v_show_full OR v_query = 'CREATE_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('                          NULL = открытая игра для присоединения любого игрока.');
            DBMS_OUTPUT.PUT_LINE('  p_ai_difficulty       - Сложность ИИ: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = PvP).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные) (необязателен, по умолчанию NULL = случайно).');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10) (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N'' (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id           - ID задачи для решения (необязателен, по умолчанию NULL = обычная игра).');
            DBMS_OUTPUT.PUT_LINE('  p_daily               - ''Y'' если это задача дня (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Игра против ИИ (Easy):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_ai_difficulty => ''E''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Решение задачи:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_puzzle_id => 10); END;');
            DBMS_OUTPUT.PUT_LINE('  -- PvP игра с таймаутами:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_game(p_opponent_username => ''BOB'', p_time_limit_move_sec => 60); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'JOIN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('JOIN_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Присоединяет вас к открытой игре или принимает прямой вызов.');
        IF v_show_full OR v_query = 'JOIN_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id - ID игры для присоединения (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_game(p_game_id => 123); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'MAKE_MOVE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('MAKE_MOVE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выполняет ход в текущей активной игре.');
        IF v_show_full OR v_query = 'MAKE_MOVE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_move_notation - Нотация хода (обязателен).');
            DBMS_OUTPUT.PUT_LINE('    Формат: ''a3-b4'' для тихого хода, ''c3:e5'' для взятия.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3-d4''); END;  -- Тихий ход');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.make_move(''c3:e5''); END;  -- Взятие');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'PRINT_ACTIVE_BOARD' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('PRINT_ACTIVE_BOARD');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выводит текущее состояние доски активной игры.');
        DBMS_OUTPUT.PUT_LINE('  - Для активных игр (статус ''A''): показывает доску с информацией об игроках и текущем ходе.');
        DBMS_OUTPUT.PUT_LINE('  - Для открытых игр (статус ''O'' или ''C''):');
        DBMS_OUTPUT.PUT_LINE('    * Без wait_for_turn: выводит сообщение "К игре еще никто не подключился".');
        DBMS_OUTPUT.PUT_LINE('    * С wait_for_turn=''Y'': ждет подключения игрока, затем показывает доску.');
        IF v_show_full OR v_query = 'PRINT_ACTIVE_BOARD' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID игры (необязателен, по умолчанию NULL). Если не указан, используется ваша активная игра.');
            DBMS_OUTPUT.PUT_LINE('  p_username      - Имя пользователя для поиска его активной игры (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('  p_wait_for_turn - ''Y'' для ожидания хода/подключения, ''N'' для немедленного вывода (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE('                    Для активных игр: ждет вашего хода.');
            DBMS_OUTPUT.PUT_LINE('                    Для открытых игр: ждет подключения другого игрока.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Просмотр активной игры:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Ожидание вашего хода (для активных игр):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Проверка открытой игры (без ожидания):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Выведет: "К игре еще никто не подключился."');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('  -- Ожидание подключения к открытой игре:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.print_active_board(p_wait_for_turn => ''Y''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Будет ждать, пока кто-то подключится, затем покажет доску.');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'RESIGN_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('RESIGN_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Сдаться в текущей активной игре.');
        IF v_show_full OR v_query = 'RESIGN_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_resign_match - ''Y'' для сдачи во всем матче, ''N'' или NULL для сдачи только в текущей игре (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.resign_game(p_resign_match => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'CANCEL_GAME' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CANCEL_GAME');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Отменяет открытую игру или вызов.');
        IF v_show_full OR v_query = 'CANCEL_GAME' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.cancel_game; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'DRAW' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('DRAW');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Управление предложениями ничьей (только для PvP игр).');
        IF v_show_full OR v_query = 'DRAW' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_action - Действие: ''O'' (предложить), ''A'' (принять), ''C'' (отменить свое предложение) (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''O''); END;  -- Предложить ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''A''); END;  -- Принять ничью');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.draw(''C''); END;  -- Отменить свое предложение');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'CREATE_MATCH' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_MATCH');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает матч (серию игр до N побед).');
        IF v_show_full OR v_query = 'CREATE_MATCH' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_opponent_username   - Имя оппонента для прямого вызова (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE('                          NULL = открытый матч для присоединения любого игрока.');
            DBMS_OUTPUT.PUT_LINE('  p_games_to_win        - Количество игр для победы в матче (необязателен, по умолчанию 3).');
            DBMS_OUTPUT.PUT_LINE('                          Должно быть нечетным числом (best of N, где N нечетное).');
            DBMS_OUTPUT.PUT_LINE('  p_player_color        - Ваш цвет: ''W'' (Белые), ''B'' (Черные) (необязателен, по умолчанию NULL = случайно).');
            DBMS_OUTPUT.PUT_LINE('  p_rule_id             - Правила: 1 (Русские 8x8), 2 (Международные 10x10) (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_move_sec - Лимит времени на ход в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_time_limit_game_sec - Лимит времени на всю партию в секундах (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_draw_moves_limit    - Лимит полуходов без взятий для ничьей (необязателен, по умолчанию NULL = без лимита).');
            DBMS_OUTPUT.PUT_LINE('  p_enable_pos_rep_draw - Включить ничью по повтору позиции: ''Y''/''N'' (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Матч с конкретным игроком:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match(p_opponent_username => ''ALICE''); END;');
            DBMS_OUTPUT.PUT_LINE('  -- Открытый матч:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match; END;');
            DBMS_OUTPUT.PUT_LINE('  -- Матч best of 5:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.create_match(p_opponent_username => ''BOB'', p_games_to_win => 5, p_rule_id => 2); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'JOIN_MATCH' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('JOIN_MATCH');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Присоединяется к матчу.');
        IF v_show_full OR v_query = 'JOIN_MATCH' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_match_id - ID матча для присоединения (обязателен).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.join_match(p_match_id => 555); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'SHOW_DAILY_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_DAILY_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает ежедневную задачу.');
        IF v_show_full OR v_query = 'SHOW_DAILY_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_daily_puzzle; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'SHOW_PUZZLES' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_PUZZLES');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает список доступных задач.');
        IF v_show_full OR v_query = 'SHOW_PUZZLES' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = все).');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id  - ID конкретной задачи для детального просмотра (необязателен, по умолчанию NULL = список всех).');
            DBMS_OUTPUT.PUT_LINE('  p_solution   - ''Y'' для показа решения (только для одной задачи по ID и только если были попытки)');
            DBMS_OUTPUT.PUT_LINE('                  (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_difficulty => ''M''); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_puzzles(p_puzzle_id => 1, p_solution => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'SHOW_MY_PUZZLES' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('SHOW_MY_PUZZLES');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Показывает задачи, созданные вами.');
        IF v_show_full OR v_query = 'SHOW_MY_PUZZLES' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty - Фильтр по сложности: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию NULL = все).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles; END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.show_my_puzzles(p_difficulty => ''H''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'CREATE_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('CREATE_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Создает новую задачу из произвольной позиции.');
        IF v_show_full OR v_query = 'CREATE_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_board_position   - Позиция доски в формате RLE (Run-Length Encoding) (обязателен).');
            DBMS_OUTPUT.PUT_LINE('                          Формат: числа обозначают количество пустых клеток, буквы - фигуры.');
            DBMS_OUTPUT.PUT_LINE('                          Пример: ''16b1b4b1b6b1b3b4b6w1b1w1w4w3w1w6w6w5w12'' (доска 10x10).');
            DBMS_OUTPUT.PUT_LINE('  p_turn_to_move     - Чей ход: ''W'' (Белые) или ''B'' (Черные) (обязателен).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_solve   - Оптимальное количество ходов для решения (необязателен, по умолчанию NULL = игра с ИИ).');
            DBMS_OUTPUT.PUT_LINE('  p_difficulty_level - Сложность: ''E'' (Easy), ''M'' (Medium), ''H'' (Hard) (необязателен, по умолчанию ''M'').');
            DBMS_OUTPUT.PUT_LINE('  p_solution         - Решение задачи в виде последовательности ходов (необязателен, по умолчанию NULL).');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  -- Пример для доски 10x10 (ход белых):');
            DBMS_OUTPUT.PUT_LINE('  BEGIN');
            DBMS_OUTPUT.PUT_LINE('    game_logic.create_puzzle(');
            DBMS_OUTPUT.PUT_LINE('      p_board_position => ''16b1b4b1b6b1b3b4b6w1b1w1w4w3w1w6w6w5w12'',');
            DBMS_OUTPUT.PUT_LINE('      p_turn_to_move => ''W''');
            DBMS_OUTPUT.PUT_LINE('    );');
            DBMS_OUTPUT.PUT_LINE('  END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'DELETE_MY_PUZZLE' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('DELETE_MY_PUZZLE');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Удаляет задачу, созданную вами.');
        IF v_show_full OR v_query = 'DELETE_MY_PUZZLE' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_puzzle_id - ID задачи для удаления (обязателен). Используйте 0 для удаления всех своих задач.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(15); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.delete_my_puzzle(0); END; -- удалить все свои задачи');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_show_all OR v_query = 'STOP_SPECTATING' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('STOP_SPECTATING');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Выход из режима просмотра игры.');
        IF v_show_full OR v_query = 'STOP_SPECTATING' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ: Нет параметров.');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.stop_spectating; END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;
    
    IF v_show_all OR v_query = 'WATCH_GAME_REPLAY' THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(c_nl || '================================================================');
        DBMS_OUTPUT.PUT_LINE('WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОПИСАНИЕ: Просматривает ходы завершенной игры пошагово.');
        IF v_show_full OR v_query = 'WATCH_GAME_REPLAY' THEN
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ:');
            DBMS_OUTPUT.PUT_LINE('  p_game_id       - ID завершенной игры (обязателен).');
            DBMS_OUTPUT.PUT_LINE('  p_moves_to_show - Количество ходов для показа за один вызов (необязателен, по умолчанию 1).');
            DBMS_OUTPUT.PUT_LINE('  p_restart       - Начать просмотр с начала (''Y'') или продолжить (''N'') (необязателен, по умолчанию ''N'').');
            DBMS_OUTPUT.PUT_LINE(c_nl);
            DBMS_OUTPUT.PUT_LINE('ПРИМЕРЫ:');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_moves_to_show => 3); END;');
            DBMS_OUTPUT.PUT_LINE('  BEGIN game_logic.watch_game_replay(p_game_id => 77, p_restart => ''Y''); END;');
        END IF;
        IF NOT v_show_all THEN RETURN; END IF;
    END IF;

    IF v_query = 'RULES' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРАВИЛА ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('РУССКИЕ ШАШКИ (rule_id = 1, доска 8x8):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно, но можно выбрать ЛЮБОЕ взятие.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит немедленно при достижении последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('МЕЖДУНАРОДНЫЕ ШАШКИ (rule_id = 2, доска 10x10):');
        DBMS_OUTPUT.PUT_LINE('  - Простая шашка: ходит на 1 клетку вперед по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Простая бьет: вперед и назад на 2 клетки (или цепочкой).');
        DBMS_OUTPUT.PUT_LINE('  - Дамка: ходит на любое число клеток по диагонали.');
        DBMS_OUTPUT.PUT_LINE('  - Дамка бьет: на любое расстояние с произвольным приземлением за бьющей.');
        DBMS_OUTPUT.PUT_LINE('  - Взятие обязательно МАКСИМАЛЬНОЕ количество фигур.');
        DBMS_OUTPUT.PUT_LINE('  - Превращение происходит при остановке на последней горизонтали.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ОБЩИЕ ПРАВИЛА:');
        DBMS_OUTPUT.PUT_LINE('  - Белые начинают первыми.');
        DBMS_OUTPUT.PUT_LINE('  - Пат (нет ходов) = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Отсутствие фигур = поражение.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: по соглашению, по лимиту ходов без взятий, по повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'RULES' THEN RETURN; END IF;
    END IF;

    IF v_query = 'PARAMETERS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПАРАМЕТРЫ ИГРЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ТАЙМАУТЫ:');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_move_sec: Лимит времени на один ход (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Если время истекает, игрок проигрывает (статус ''T'' - Timeout).');
        DBMS_OUTPUT.PUT_LINE('    Джоб таймаута создается при join_game и переносится при каждом ходе.');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 30 секунд.');
        DBMS_OUTPUT.PUT_LINE('  - p_time_limit_game_sec: Лимит времени на всю партию (в секундах).');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 600 секунд (10 минут).');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('НИЧЬИ:');
        DBMS_OUTPUT.PUT_LINE('  - p_draw_moves_limit: Количество полуходов без взятий для автоматической ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Например, 15 означает, что после 15 полуходов без взятий игра заканчивается ничьей.');
        DBMS_OUTPUT.PUT_LINE('    Минимум: 5.');
        DBMS_OUTPUT.PUT_LINE('  - p_enable_pos_rep_draw: ''Y'' включает ничью по троекратному повтору позиции.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        
        DBMS_OUTPUT.PUT_LINE('ПРИМЕР ИГРЫ С ВСЕМИ ПАРАМЕТРАМИ:');
        DBMS_OUTPUT.PUT_LINE('  BEGIN');
        DBMS_OUTPUT.PUT_LINE('    game_logic.create_game(');
        DBMS_OUTPUT.PUT_LINE('      p_opponent_username => ''BOB'',');
        DBMS_OUTPUT.PUT_LINE('      p_player_color => ''W'',');
        DBMS_OUTPUT.PUT_LINE('      p_rule_id => 1,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_move_sec => 60,');
        DBMS_OUTPUT.PUT_LINE('      p_time_limit_game_sec => 3600,');
        DBMS_OUTPUT.PUT_LINE('      p_draw_moves_limit => 15,');
        DBMS_OUTPUT.PUT_LINE('      p_enable_pos_rep_draw => ''Y''');
        DBMS_OUTPUT.PUT_LINE('    );');
        DBMS_OUTPUT.PUT_LINE('  END;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'PARAMETERS' THEN RETURN; END IF;
    END IF;

    IF v_query = 'STATUSES' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('СТАТУСЫ ИГР');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  ''O'' - Open (Открытая, ждет соперника)');
        DBMS_OUTPUT.PUT_LINE('  ''C'' - Challenged (Вызов, ждет принятия)');
        DBMS_OUTPUT.PUT_LINE('  ''A'' - Active (Активная, идет игра)');
        DBMS_OUTPUT.PUT_LINE('  ''V'' - Victory (Победа одного из игроков)');
        DBMS_OUTPUT.PUT_LINE('  ''D'' - Draw (Ничья)');
        DBMS_OUTPUT.PUT_LINE('  ''T'' - Timeout (Таймаут)');
        DBMS_OUTPUT.PUT_LINE('  ''R'' - Resigned (Сдача)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'STATUSES' THEN RETURN; END IF;
    END IF;

    IF v_query = 'VIEWS' OR v_show_full THEN
        IF v_query = 'VIEWS' THEN
            v_found := TRUE;
        END IF;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ (VIEWS) ДЛЯ СТАТИСТИКИ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ БЕЗ ПАРАМЕТРОВ:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_games;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные игры (со статусом партии):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_games WHERE game_id = 123;  -- статус конкретной игры');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Открытые матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_open_matches;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Активные матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_active_matches;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Правила игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_rules;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('ПРЕДСТАВЛЕНИЯ С ФИЛЬТРАМИ:');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Протокол партии (все ходы со статусом):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_game_protocol WHERE game_id = 123 ORDER BY move_number;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Завершенные игры:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_games WHERE match_id IS NOT NULL;  -- игры из матчей');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Завершенные матчи:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_matches;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_ended_matches WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Детали матча (все игры в матче):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_match_details WHERE match_id = 10 ORDER BY game_id;');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- История игрока (все партии всех игроков):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE player_name = USER;  -- моя история');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE rule_id = 1;  -- русские шашки (1=русские, 2=международные)');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE start_time >= DATE ''2025-01-01'' AND end_time <= DATE ''2025-01-31'';  -- за период');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_history WHERE match_id IS NOT NULL;  -- игры из матчей');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Рейтинги/топ (все игроки, все сезоны):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings WHERE season_id = 5;  -- конкретный сезон');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_player_ratings WHERE rule_id = 1;  -- русские шашки');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        DBMS_OUTPUT.PUT_LINE('  -- Результаты Daily Puzzles (только для тех, кто решал):');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results;');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM v_daily_puzzle_results WHERE player_name = USER;  -- мои результаты');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'VIEWS' THEN RETURN; END IF;
    END IF;

    IF v_query = 'RATINGS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('РЕЙТИНГИ И СЕЗОНЫ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Начальный рейтинг нового игрока: 500 для всех правил.');
        DBMS_OUTPUT.PUT_LINE('  - Победа в обычной игре: +16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Поражение в обычной игре: -16 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Решение задачи (первый раз): +5 очков.');
        DBMS_OUTPUT.PUT_LINE('  - Ничья: рейтинг не меняется.');
        DBMS_OUTPUT.PUT_LINE('  - Минимальный рейтинг: 0 (не может быть отрицательным).');
        DBMS_OUTPUT.PUT_LINE('  - Сезоны обновляются автоматически каждый месяц (scheduler).');
        DBMS_OUTPUT.PUT_LINE('  - Формат сезона: "Месяц-Год" (например, "Январь-2025").');
        DBMS_OUTPUT.PUT_LINE('  - При создании нового сезона триггер trg_init_season_ratings автоматически');
        DBMS_OUTPUT.PUT_LINE('    создает рейтинги для всех игроков по формуле: rating * 0.8 (минимум 500).');
        DBMS_OUTPUT.PUT_LINE('    Если рейтинг < 500, он остается 500.');
        DBMS_OUTPUT.PUT_LINE('  - Матч: +16 за победу в игре, -16 за поражение, +10*N бонус за матч (N = games_to_win)');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'RATINGS' THEN RETURN; END IF;
    END IF;

    IF v_query = 'CONSTRAINTS' OR v_show_full THEN
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('ОГРАНИЧЕНИЯ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('  - Один пользователь может иметь только одну активную сессию.');
        DBMS_OUTPUT.PUT_LINE('  - Активная сессия = игра (статус ''A'', ''O'', ''C'') или просмотр (spectating).');
        DBMS_OUTPUT.PUT_LINE('  - При попытке создать вторую игру будет ошибка.');
        DBMS_OUTPUT.PUT_LINE('  - Длительное простаивание автоматически завершает сессию (scheduler, 24 часа).');
        DBMS_OUTPUT.PUT_LINE('  - Лимит времени на ход: минимум 30 секунд.');
        DBMS_OUTPUT.PUT_LINE('  - Лимит времени на партию: минимум 600 секунд (10 минут).');
        DBMS_OUTPUT.PUT_LINE('  - Лимит полуходов без взятий: минимум 5.');
        DBMS_OUTPUT.PUT_LINE(c_nl);
        IF v_query = 'CONSTRAINTS' THEN RETURN; END IF;
    END IF;

    IF NOT v_show_all AND NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка: Процедура или запрос "' || v_query || '" не найден.');
        DBMS_OUTPUT.PUT_LINE('Доступные процедуры: CREATE_GAME, JOIN_GAME, MAKE_MOVE, PRINT_ACTIVE_BOARD,');
        DBMS_OUTPUT.PUT_LINE('  RESIGN_GAME, CANCEL_GAME, DRAW, CREATE_MATCH, JOIN_MATCH,');
        DBMS_OUTPUT.PUT_LINE('  SHOW_DAILY_PUZZLE, SHOW_PUZZLES, SHOW_MY_PUZZLES, CREATE_PUZZLE,');
        DBMS_OUTPUT.PUT_LINE('  DELETE_MY_PUZZLE, STOP_SPECTATING, WATCH_GAME_REPLAY');
        DBMS_OUTPUT.PUT_LINE('Доступные запросы: ALL (полная справка), VIEWS (информация о представлениях)');
        DBMS_OUTPUT.PUT_LINE('Для полной справки: BEGIN game_logic.info(p_query => ''ALL''); END;');
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при выводе справки: ' || SQLERRM);
END info;

PROCEDURE p_process_inactive_timeouts(
    p_timeout_hours IN NUMBER DEFAULT 24
) IS
    v_updated_count PLS_INTEGER := 0;
    v_decoded_board VARCHAR2(100);
    v_score NUMBER;
    v_winner_color CHAR(1);
    c_man_value      CONSTANT NUMBER := 1;
    c_king_value     CONSTANT NUMBER := 4;
    c_empty_field    CONSTANT CHAR(1) := '+';
BEGIN

    FOR r IN (
        SELECT g.game_id, g.rule_id, g.current_turn
        FROM games g
        WHERE g.status = 'A'
          AND (

              (EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
               AND (SELECT MAX(move_timestamp) FROM game_moves WHERE game_id = g.game_id) < SYSDATE - (p_timeout_hours / 24))
              OR

              (NOT EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
               AND g.start_time < SYSDATE - (p_timeout_hours / 24))
          )
    ) LOOP
        BEGIN

            BEGIN
                SELECT decode_board(board_position) INTO v_decoded_board
                FROM game_moves
                WHERE game_id = r.game_id
                ORDER BY move_number DESC
                FETCH FIRST 1 ROW ONLY;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN

                    v_decoded_board := get_initial_position(r.rule_id);
            END;

            DECLARE
                v_piece          CHAR(1);
                v_total_squares  NUMBER;
                v_board_size     NUMBER;
            BEGIN
                v_total_squares := LENGTH(v_decoded_board);
                v_board_size    := SQRT(v_total_squares);
                p_init_board_map(v_board_size);
                
                v_score := 0;
                FOR i IN 1..v_total_squares LOOP
                    v_piece := SUBSTR(v_decoded_board, i, 1);
                    
                    IF v_piece != c_empty_field THEN
                        DECLARE
                            v_piece_value    NUMBER;
                            v_multiplier     NUMBER;
                        BEGIN

                            IF v_piece IN ('w', 'W') THEN
                                v_multiplier := 1;
                            ELSE
                                v_multiplier := -1;
                            END IF;

                            v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                            
                            v_score := v_score + (v_piece_value * v_multiplier);
                        END;
                    END IF;
                END LOOP;
            END;

            IF v_score > 0 THEN
                v_winner_color := 'W';
            ELSIF v_score < 0 THEN
                v_winner_color := 'B';
            ELSE

                v_winner_color := CASE WHEN r.current_turn = 'W' THEN 'B' ELSE 'W' END;
            END IF;

            p_finish_game(
                p_game_id      => r.game_id,
                p_status       => 'T',
                p_winner_color => v_winner_color,
                p_audit_event  => 'INACTIVE_GAME_TIMEOUT: Score=' || v_score || ', Winner=' || v_winner_color,
                p_player_id    => NULL
            );
            
            v_updated_count := v_updated_count + 1;
        EXCEPTION
            WHEN OTHERS THEN

                NULL;
        END;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN

        NULL;
END p_process_inactive_timeouts;

BEGIN
    NULL;
END game_logic;
