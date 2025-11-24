-- @procedure create_match
-- @brief Creates a new match (a series of games).
-- @dependencies:
--   - players (table)
--   - matches (table)
--   - games (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)
--   - create_game (procedure)

PROCEDURE create_match(
    p_opponent_username   IN VARCHAR2,
    p_games_to_win        IN NUMBER,
    p_player_color        IN CHAR     DEFAULT NULL,
    p_rule_id             IN NUMBER   DEFAULT 1,
    p_time_limit_move_sec IN NUMBER   DEFAULT NULL,
    p_time_limit_game_sec IN NUMBER   DEFAULT NULL,
    p_draw_moves_limit    IN NUMBER   DEFAULT NULL,
    p_enable_pos_rep_draw IN CHAR     DEFAULT 'N'
) IS
    v_current_player_id  players.player_id%TYPE;
    v_opponent_player_id players.player_id%TYPE;
    v_error_msg          VARCHAR2(255);
    v_status_message     VARCHAR2(255);
    
    v_game_id            games.game_id%TYPE;
    v_match_id           matches.match_id%TYPE;
    
BEGIN
    v_current_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_current_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы уже заняты в активной сессии (игре или просмотре).';
        p_audit_log(v_current_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    IF p_games_to_win IS NULL OR p_games_to_win <= 0 THEN
        v_error_msg := 'Неверное количество игр для победы (p_games_to_win).';
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

    INSERT INTO matches (
        rule_id, 
        games_to_win, 
        status
    )
    SELECT 
        g.rule_id,
        p_games_to_win,
        g.status
    FROM games g
    WHERE g.game_id = v_game_id
    RETURNING match_id INTO v_match_id;

    UPDATE games
    SET match_id = v_match_id
    WHERE game_id = v_game_id;
    
    IF p_opponent_username IS NOT NULL THEN
        v_status_message := 'Вызов на матч (ID: ' || v_match_id || ') до ' || p_games_to_win || ' побед брошен игроку ' || p_opponent_username;
    ELSE
        v_status_message := 'Открытый матч (ID: ' || v_match_id || ') до ' || p_games_to_win || ' побед создан. Ожидайте оппонента.';
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