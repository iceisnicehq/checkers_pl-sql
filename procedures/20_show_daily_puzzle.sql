-- @procedure show_daily_puzzle
-- @brief Shows the daily puzzle.
-- @dependencies:
--   - daily_puzzles (table)
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - p_audit_log (procedure)
--   - rec_daily_puzzle_info (type)

PROCEDURE show_daily_puzzle IS
    v_today DATE := TRUNC(SYSDATE);
    v_puzzle_info rec_daily_puzzle_info;
    v_player_id players.player_id%TYPE;
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    BEGIN
        SELECT 
            dp.puzzle_date,
            p.puzzle_id,
            p.difficulty_level,
            p.moves_to_solve,
            p.turn_to_move,
            p.board_position
        INTO v_puzzle_info
        FROM daily_puzzles dp
        JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
        WHERE dp.puzzle_date = v_today;
        
        DBMS_OUTPUT.PUT_LINE('--- Задача Дня (' || TO_CHAR(v_today, 'DD.MM.YYYY') || ') ---');
        DBMS_OUTPUT.PUT_LINE('ID Задачи:   ' || v_puzzle_info.puzzle_id);
        DBMS_OUTPUT.PUT_LINE('Сложность:   ' || v_puzzle_info.difficulty_level);
        DBMS_OUTPUT.PUT_LINE('Ходов:       ' || NVL(TO_CHAR(v_puzzle_info.moves_to_solve), 'N/A'));
        DBMS_OUTPUT.PUT_LINE('Ход:         ' || v_puzzle_info.turn_to_move);
        DBMS_OUTPUT.PUT_LINE('Позиция:     ' || v_puzzle_info.board_position);
        DBMS_OUTPUT.PUT_LINE('---');
        DBMS_OUTPUT.PUT_LINE('Для решения, вызовите: EXEC game_logic.start_daily_puzzle;');

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка: Задача на ' || TO_CHAR(v_today, 'DD.MM.YYYY') || ' еще не назначена.');
            p_audit_log(NULL, NULL, p_event_msg => 'DAILY_PUZZLE_NOT_FOUND');
    END;
END show_daily_puzzle;