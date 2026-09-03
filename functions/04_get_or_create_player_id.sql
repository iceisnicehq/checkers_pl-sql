FUNCTION get_or_create_player_id(p_username IN VARCHAR2) RETURN NUMBER IS
    v_player_id players.player_id%TYPE;
    v_current_season_id seasons.season_id%TYPE;
BEGIN
    BEGIN
        SELECT player_id
        INTO v_player_id
        FROM players
        WHERE username = p_username;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO players (username)
            VALUES (p_username)
            RETURNING player_id INTO v_player_id;
            
            BEGIN
                SELECT season_id INTO v_current_season_id
                FROM seasons
                WHERE SYSDATE BETWEEN start_date AND end_date
                AND ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Если активного сезона нет, берем последний созданный
                    SELECT MAX(season_id) INTO v_current_season_id FROM seasons;
            END;
            
            IF v_current_season_id IS NOT NULL THEN
                FOR r IN (SELECT rule_id FROM game_rules) LOOP
                    BEGIN
                        INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                        VALUES (v_player_id, r.rule_id, v_current_season_id, 500);
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                END LOOP;
            END IF;
    END;
    RETURN v_player_id;
END get_or_create_player_id;
