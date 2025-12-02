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