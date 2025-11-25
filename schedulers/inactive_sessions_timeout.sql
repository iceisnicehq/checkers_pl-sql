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
            v_updated_count PLS_INTEGER;
        BEGIN
            -- Завершаем игры со статусом 'A' (Active), которые неактивны дольше таймаута
            -- Используем last_move_at если есть, иначе start_time
            UPDATE games g
            SET status = 'T', -- Timeout
                end_time = SYSDATE,
                winner_player_color = CASE 
                    WHEN g.current_turn = 'W' THEN 'B' 
                    ELSE 'W' 
                END
            WHERE g.status = 'A'
              AND (
                  -- Если есть ходы, проверяем последний ход
                  (EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
                   AND (SELECT MAX(move_timestamp) FROM game_moves WHERE game_id = g.game_id) < SYSDATE - (v_timeout_hours / 24))
                  OR
                  -- Если ходов нет, проверяем время начала
                  (NOT EXISTS (SELECT 1 FROM game_moves gm WHERE gm.game_id = g.game_id)
                   AND g.start_time < SYSDATE - (v_timeout_hours / 24))
              );
            
            v_updated_count := SQL%ROWCOUNT;
            
            IF v_updated_count > 0 THEN
                -- Обновляем рейтинги для завершенных игр
                FOR r IN (SELECT game_id FROM games WHERE status = 'T' AND end_time >= SYSDATE - 1/24) LOOP
                    BEGIN
                        C##CHECKERS_APP.game_logic.p_update_ratings(r.game_id);
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                END LOOP;
                
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

