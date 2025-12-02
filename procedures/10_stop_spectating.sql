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