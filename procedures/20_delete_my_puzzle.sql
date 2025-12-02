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