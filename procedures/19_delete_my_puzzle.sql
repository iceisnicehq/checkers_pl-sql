-- @procedure delete_my_puzzle
-- @brief Deletes a puzzle created by the current user.
-- @dependencies:
--   - puzzles (table)
--   - get_or_create_player_id (function)
--   - get_active_game (function)
--   - p_audit_log (procedure)

PROCEDURE delete_my_puzzle(p_puzzle_id IN NUMBER) IS
    v_player_id players.player_id%TYPE;
    v_error_msg VARCHAR2(255);
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    IF get_active_game(v_player_id) IS NOT NULL THEN
        v_error_msg := 'Вы заняты в активной сессии. Завершите игру или просмотр, чтобы удалить задачу.';
        p_audit_log(v_player_id, NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN;
    END IF;

    BEGIN
        DELETE FROM puzzles
        WHERE puzzle_id = p_puzzle_id
          AND created_by_player_id = v_player_id;
          
        IF SQL%ROWCOUNT = 0 THEN
            DECLARE
                v_count PLS_INTEGER;
            BEGIN
                SELECT 1 INTO v_count FROM puzzles WHERE puzzle_id = p_puzzle_id;
                v_error_msg := 'Ошибка: Невозможно удалить задачу. Она не существует или не принадлежит вам.';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_error_msg := 'Ошибка: Задача с ID ' || p_puzzle_id || ' не существует.';
            END;
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            ROLLBACK;
        ELSE
            DBMS_OUTPUT.PUT_LINE('Задача (ID: ' || p_puzzle_id || ') успешно удалена.');
            p_audit_log(v_player_id, NULL, p_event_msg => 'PUZZLE_DELETED');
            COMMIT;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF SQLCODE = -2292 THEN
                v_error_msg := 'Ошибка: Невозможно удалить задачу. Она используется (или использовалась) как "Задача Дня".';
            ELSE
                v_error_msg := 'Ошибка при удалении: ' || SQLERRM;
            END IF;
            p_audit_log(v_player_id, NULL, p_event_msg => SUBSTR(v_error_msg, 1, 255));
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
    END;
END delete_my_puzzle;