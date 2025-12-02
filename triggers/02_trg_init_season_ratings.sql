
CREATE OR REPLACE TRIGGER trg_init_season_ratings
    AFTER INSERT ON seasons
    FOR EACH ROW
BEGIN
    INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
    SELECT 
        pr_old.player_id,
        pr_old.rule_id,
        :NEW.season_id,
        GREATEST(500, ROUND(pr_old.rating * 0.8))
    FROM player_ratings pr_old
    WHERE pr_old.season_id = (
        SELECT MAX(season_id)
        FROM seasons
        WHERE season_id < :NEW.season_id
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM player_ratings pr_new 
        WHERE pr_new.player_id = pr_old.player_id 
          AND pr_new.rule_id = pr_old.rule_id 
          AND pr_new.season_id = :NEW.season_id
    );
END;
