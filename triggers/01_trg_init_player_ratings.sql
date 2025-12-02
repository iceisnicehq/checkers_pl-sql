
CREATE OR REPLACE TRIGGER trg_init_player_ratings
    AFTER INSERT ON players
    FOR EACH ROW
DECLARE
    v_season_id seasons.season_id%TYPE;
BEGIN
    BEGIN
        SELECT season_id INTO v_season_id
        FROM seasons
        WHERE SYSDATE BETWEEN start_date AND end_date
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            SELECT MAX(season_id) INTO v_season_id 
            FROM seasons;
    END;
    
    IF v_season_id IS NOT NULL THEN
        INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
        SELECT :NEW.player_id, rule_id, v_season_id, 500
        FROM game_rules;
    END IF;
END;

