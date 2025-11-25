PROCEDURE stop_spectating IS
    v_player_id players.player_id%TYPE;
    v_count     PLS_INTEGER;
BEGIN
    v_player_id := get_or_create_player_id(USER);
    
    UPDATE spectators
    SET left_at = SYSDATE
    WHERE player_id = v_player_id
      AND left_at IS NULL
    RETURNING COUNT(*) INTO v_count;
    
    COMMIT;
    
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Вы вышли из режима просмотра.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Вы не находились в режиме просмотра.');
    END IF;
    
END stop_spectating;
