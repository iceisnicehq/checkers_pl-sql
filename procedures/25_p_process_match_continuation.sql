PROCEDURE p_process_match_continuation(p_match_id IN NUMBER, p_completed_game_id IN NUMBER) IS
    v_match matches%ROWTYPE;
    v_completed_game games%ROWTYPE;
    v_player1_id players.player_id%TYPE;
    v_player2_id players.player_id%TYPE;
    v_player1_wins NUMBER := 0;
    v_player2_wins NUMBER := 0;
    v_games_to_win NUMBER;
    v_next_game_id NUMBER;
    v_next_player_color CHAR(1);
    v_error_msg VARCHAR2(255);
BEGIN
    BEGIN
        SELECT * INTO v_match FROM matches WHERE match_id = p_match_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;
    
    IF v_match.status = 'C' THEN
        RETURN;
    END IF;
    
    BEGIN
        SELECT * INTO v_completed_game FROM games WHERE game_id = p_completed_game_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;
    
    DECLARE
        v_first_game games%ROWTYPE;
    BEGIN
        SELECT * INTO v_first_game 
        FROM games 
        WHERE match_id = p_match_id 
        ORDER BY game_id ASC 
        FETCH FIRST 1 ROW ONLY;
        
        v_player1_id := v_first_game.player_white_id;
        v_player2_id := v_first_game.player_black_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;
    
    FOR r IN (
        SELECT winner_player_color, status
        FROM games
        WHERE match_id = p_match_id
          AND status IN ('V', 'D', 'T', 'R')
    ) LOOP
        IF r.status = 'V' THEN
            IF r.winner_player_color = 'W' AND v_player1_id IS NOT NULL THEN
                v_player1_wins := v_player1_wins + 1;
            ELSIF r.winner_player_color = 'B' AND v_player2_id IS NOT NULL THEN
                v_player2_wins := v_player2_wins + 1;
            END IF;
        END IF;
    END LOOP;
    
    v_games_to_win := v_match.games_to_win;
    
    IF v_player1_wins >= v_games_to_win THEN
        UPDATE matches
        SET status = 'C',
            winner_player_id = v_player1_id
        WHERE match_id = p_match_id;
        p_audit_log(v_player1_id, p_completed_game_id, 'MATCH_WON');
        RETURN;
    ELSIF v_player2_wins >= v_games_to_win THEN
        UPDATE matches
        SET status = 'C',
            winner_player_id = v_player2_id
        WHERE match_id = p_match_id;
        p_audit_log(v_player2_id, p_completed_game_id, 'MATCH_WON');
        RETURN;
    END IF;
    
    DECLARE
        v_game_count NUMBER;
        v_creator_id players.player_id%TYPE;
        v_opponent_id players.player_id%TYPE;
    BEGIN
        SELECT COUNT(*) INTO v_game_count
        FROM games
        WHERE match_id = p_match_id;
        
        IF MOD(v_game_count, 2) = 0 THEN
            v_creator_id := v_player1_id;
            v_opponent_id := v_player2_id;
            v_next_player_color := 'B';
        ELSE
            v_creator_id := v_player1_id;
            v_opponent_id := v_player2_id;
            v_next_player_color := 'W';
        END IF;
        
        DECLARE
            v_first_game games%ROWTYPE;
        BEGIN
            SELECT * INTO v_first_game
            FROM games
            WHERE match_id = p_match_id
            ORDER BY game_id ASC
            FETCH FIRST 1 ROW ONLY;
            
            INSERT INTO games (
                match_id, rule_id, player_white_id, player_black_id,
                creator_player_color, status, current_turn,
                time_limit_move_sec, time_limit_game_sec,
                draw_moves_limit, enable_pos_repetition_draw
            )
            VALUES (
                p_match_id, v_first_game.rule_id,
                CASE v_next_player_color WHEN 'W' THEN v_creator_id ELSE v_opponent_id END,
                CASE v_next_player_color WHEN 'W' THEN v_opponent_id ELSE v_creator_id END,
                v_next_player_color, 'C', 'W',
                v_first_game.time_limit_move_sec,
                v_first_game.time_limit_game_sec,
                v_first_game.draw_moves_limit,
                v_first_game.enable_pos_repetition_draw
            )
            RETURNING game_id INTO v_next_game_id;
            
            p_audit_log(v_creator_id, v_next_game_id, 'MATCH_NEXT_GAME_CREATED');
        END;
    END;
    
EXCEPTION
    WHEN OTHERS THEN
        p_audit_log(NULL, p_completed_game_id, 'MATCH_CONTINUATION_ERROR: ' || SQLERRM);
END p_process_match_continuation;

