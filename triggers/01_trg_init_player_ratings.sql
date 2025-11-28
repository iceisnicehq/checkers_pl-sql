-- =========================================================================
-- ТРИГГЕР: trg_init_player_ratings
-- =========================================================================
-- Автоматически создает начальные рейтинги (500) для нового игрока
-- для всех правил игры в текущем сезоне.
-- Использует set-based подход (INSERT ... SELECT) вместо цикла.
-- =========================================================================

CREATE OR REPLACE TRIGGER trg_init_player_ratings
    AFTER INSERT ON players
    FOR EACH ROW
DECLARE
    v_season_id seasons.season_id%TYPE;
BEGIN
    -- 1. Получаем ID текущего сезона (активный или последний созданный)
    BEGIN
        SELECT season_id INTO v_season_id
        FROM seasons
        WHERE SYSDATE BETWEEN start_date AND end_date
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Если активного сезона нет, берем последний созданный
            SELECT MAX(season_id) INTO v_season_id 
            FROM seasons;
    END;
    
    -- 2. Set-based вставка рейтингов для всех правил (без цикла)
    IF v_season_id IS NOT NULL THEN
        INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
        SELECT :NEW.player_id, rule_id, v_season_id, 500
        FROM game_rules;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Игнорируем ошибки создания рейтингов (например, если сезонов нет вообще)
        -- Это не должно блокировать создание игрока
        NULL;
END;
/

