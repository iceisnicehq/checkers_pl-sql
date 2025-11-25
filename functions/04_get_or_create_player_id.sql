-- @function get_or_create_player_id
-- @brief Retrieves the player_id for a given username, creating the player if it doesn't exist.
-- @dependencies:
--   - players (table)

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
            
            -- Создаем начальные рейтинги для нового игрока (500 по умолчанию)
            -- Для всех правил и текущего сезона
            BEGIN
                -- Получаем текущий сезон
                SELECT season_id INTO v_current_season_id
                FROM seasons
                WHERE SYSDATE BETWEEN start_date AND end_date
                AND ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Если сезона нет, берем последний созданный или создаем новый
                    BEGIN
                        SELECT MAX(season_id) INTO v_current_season_id FROM seasons;
                        IF v_current_season_id IS NULL THEN
                            -- Создаем сезон если его нет
                            DECLARE
                                v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
                                    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                                    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
                                );
                                v_month_num PLS_INTEGER := EXTRACT(MONTH FROM SYSDATE);
                                v_year_num PLS_INTEGER := EXTRACT(YEAR FROM SYSDATE);
                                v_season_name VARCHAR2(100) := v_month_names(v_month_num) || '-' || v_year_num;
                                v_start_date DATE := TRUNC(SYSDATE, 'MM');
                                v_end_date DATE := ADD_MONTHS(v_start_date, 1) - 1;
                            BEGIN
                                INSERT INTO seasons (season_name, start_date, end_date)
                                VALUES (v_season_name, v_start_date, v_end_date)
                                RETURNING season_id INTO v_current_season_id;
                            END;
                        END IF;
                    END;
            END;
            
            -- Создаем рейтинги для всех правил
            IF v_current_season_id IS NOT NULL THEN
                FOR r IN (SELECT rule_id FROM game_rules) LOOP
                    BEGIN
                        INSERT INTO player_ratings (player_id, rule_id, season_id, rating)
                        VALUES (v_player_id, r.rule_id, v_current_season_id, 500);
                    EXCEPTION
                        WHEN OTHERS THEN NULL; -- Игнорируем ошибки
                    END;
                END LOOP;
            END IF;
    END;
    RETURN v_player_id;
END get_or_create_player_id;