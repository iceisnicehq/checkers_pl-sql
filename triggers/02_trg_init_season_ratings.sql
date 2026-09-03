-- =========================================================================
-- ТРИГГЕР: trg_init_season_ratings
-- =========================================================================
-- Автоматически создает рейтинги для всех игроков при создании нового сезона.
-- Формула: новый_рейтинг = старый_рейтинг * 0.8 (минимум 500).
-- Если рейтинг < 500, он остается 500.
-- =========================================================================

CREATE OR REPLACE TRIGGER trg_init_season_ratings
    AFTER INSERT ON seasons
    FOR EACH ROW
BEGIN
    -- Создаем рейтинги для всех игроков на основе предыдущего сезона
    -- Формула: rating * 0.8 (минимум 500)
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
EXCEPTION
    WHEN OTHERS THEN
        -- Игнорируем ошибки создания рейтингов
        -- Это не должно блокировать создание сезона
        NULL;
END;
/

