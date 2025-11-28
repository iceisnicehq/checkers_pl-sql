BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'INACTIVE_SESSIONS_TIMEOUT_JOB');
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'INACTIVE_SESSIONS_TIMEOUT_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
        DECLARE
            v_timeout_hours NUMBER := 24; -- Таймаут неактивности: 24 часа
            v_updated_count PLS_INTEGER := 0;
            v_board_position VARCHAR2(100);
            v_decoded_board VARCHAR2(100);
            v_score NUMBER;
            v_winner_color CHAR(1);
        BEGIN
            -- Завершаем игры со статусом 'A' (Active), которые неактивны дольше таймаута
            -- Оцениваем позицию и определяем победителя по лучшей позиции
            FOR r IN (
                SELECT g.game_id, g.rule_id, g.current_turn
                FROM games g
                WHERE g.status = 'A'
                  AND (
                      -- Если есть ходы, проверяем последний ход
                      (EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
                       AND (SELECT MAX(move_timestamp) FROM game_moves WHERE game_id = g.game_id) < SYSDATE - (v_timeout_hours / 24))
                      OR
                      -- Если ходов нет, проверяем время начала
                      (NOT EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
                       AND g.start_time < SYSDATE - (v_timeout_hours / 24))
                  )
            ) LOOP
                BEGIN
                    -- Получаем текущую позицию доски
                    BEGIN
                        SELECT C##CHECKERS_APP.game_logic.decode_board(board_position) INTO v_decoded_board
                        FROM game_moves
                        WHERE game_id = r.game_id
                        ORDER BY move_number DESC
                        FETCH FIRST 1 ROW ONLY;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            -- Если ходов нет, используем начальную позицию
                            v_decoded_board := C##CHECKERS_APP.game_logic.get_initial_position(r.rule_id);
                    END;
                    
                    -- Оцениваем позицию (положительная = лучше для белых, отрицательная = лучше для черных)
                    -- Соотношение: шашка = 1, дамка = 4 (1 дамка = 4 шашки)
                    DECLARE
                        v_piece          CHAR(1);
                        v_total_squares  NUMBER;
                        v_board_size     NUMBER;
                        c_man_value      CONSTANT NUMBER := 1;  -- Шашка = 1
                        c_king_value     CONSTANT NUMBER := 4;  -- Дамка = 4
                        c_empty_field    CONSTANT CHAR(1) := '+';  -- Пустое поле
                    BEGIN
                        v_total_squares := LENGTH(v_decoded_board);
                        v_board_size    := SQRT(v_total_squares);
                        C##CHECKERS_APP.game_logic.p_init_board_map(v_board_size);
                        
                        v_score := 0;
                        FOR i IN 1..v_total_squares LOOP
                            v_piece := SUBSTR(v_decoded_board, i, 1);
                            
                            IF v_piece != c_empty_field THEN
                                DECLARE
                                    v_piece_value    NUMBER;
                                    v_multiplier     NUMBER;
                                BEGIN
                                    -- Определяем цвет и множитель
                                    IF v_piece IN ('w', 'W') THEN
                                        v_multiplier := 1; -- Белые - положительные
                                    ELSE
                                        v_multiplier := -1; -- Черные - отрицательные
                                    END IF;
                                    
                                    -- Оценка материала (шашка = 1, дамка = 4)
                                    v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                                    
                                    v_score := v_score + (v_piece_value * v_multiplier);
                                END;
                            END IF;
                        END LOOP;
                    END;
                    
                    -- Определяем победителя по оценке позиции
                    IF v_score > 0 THEN
                        v_winner_color := 'W'; -- Белые в лучшей позиции
                    ELSIF v_score < 0 THEN
                        v_winner_color := 'B'; -- Черные в лучшей позиции
                    ELSE
                        -- Если оценка равна 0 (ничья), побеждает тот, чей сейчас ход (проигравший по таймауту)
                        v_winner_color := CASE WHEN r.current_turn = 'W' THEN 'B' ELSE 'W' END;
                    END IF;
                    
                    -- Обновляем игру
                    UPDATE games
                    SET status = 'T', -- Timeout
                        end_time = SYSDATE,
                        winner_player_color = v_winner_color
                    WHERE game_id = r.game_id;
                    
                    -- Закрываем зрителей
                    UPDATE spectators 
                    SET left_at = SYSDATE 
                    WHERE game_id = r.game_id AND left_at IS NULL;
                    
                    -- Обновляем рейтинги
                    C##CHECKERS_APP.game_logic.p_update_ratings(r.game_id);
                    
                    -- Логируем событие
                    C##CHECKERS_APP.game_logic.p_audit_log(NULL, r.game_id, 'INACTIVE_GAME_TIMEOUT: Score=' || v_score || ', Winner=' || v_winner_color);
                    
                    v_updated_count := v_updated_count + 1;
                EXCEPTION
                    WHEN OTHERS THEN
                        -- Если ошибка при обработке одной игры, продолжаем с другими
                        NULL;
                END;
            END LOOP;
            
            IF v_updated_count > 0 THEN
                COMMIT;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- Логируем ошибку но не падаем
                NULL;
        END;
    ]',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=HOURLY; BYMINUTE=0', -- Каждый час
    enabled         => TRUE,
    comments        => 'Automatically closes inactive game sessions after timeout period.'
  );
  
  DBMS_OUTPUT.PUT_LINE('Job INACTIVE_SESSIONS_TIMEOUT_JOB успешно создан.');
END;
/

