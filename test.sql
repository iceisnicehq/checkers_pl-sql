-- Выполняем из-под пользователя PLAYER1
SET SERVEROUTPUT ON;

DECLARE
    v_new_game_id NUMBER;
BEGIN
    -- PLAYER1 создает игру против PLAYER2
    game_logic.create_game(
        p_opponent_username => 'PLAYER2',
        p_game_id           => v_new_game_id
    );

    DBMS_OUTPUT.PUT_LINE('Успешно создана новая партия с ID: ' || v_new_game_id);

    -- Проверим, что партия появилась в таблице
    FOR r_game IN (SELECT * FROM games WHERE game_id = v_new_game_id) LOOP
        DBMS_OUTPUT.PUT_LINE('Статус: ' || r_game.status);
        DBMS_OUTPUT.PUT_LINE('Позиция: ' || r_game.board_position);
    END LOOP;
END;
/