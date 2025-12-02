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