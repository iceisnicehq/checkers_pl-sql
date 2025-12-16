-- Скрипт для создания тестовых данных для проверки масштабируемости
-- Создает 100 тыс партий между игроками с ID 1 и 2
-- В каждой партии по 10 ходов
-- Итого: 1 млн ходов

SET SERVEROUTPUT ON;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';

DECLARE
    v_player1_id NUMBER := 1;
    v_player2_id NUMBER := 2;
    v_rule_id NUMBER := 2; -- Международные шашки 10x10
    v_total_games NUMBER := 100000;
    v_moves_per_game NUMBER := 10;
    v_game_id NUMBER;
    v_move_number NUMBER;
    v_current_turn CHAR(1) := 'W';
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_elapsed_seconds NUMBER;
    
    -- Позиции доски после каждого хода (из реальной игры)
    TYPE board_array IS TABLE OF VARCHAR2(200);
    v_boards board_array := board_array(
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1bb1b1b1b1b11w12w1w1w1ww1w1w1w1w2w1w1w1w1ww1w1w1w1w1',  -- После хода 1
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b2b1b1b1b2b8w12w1w1w1ww1w1w1w1w2w1w1w1w1ww1w1w1w1w1',  -- После хода 2
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b2b1b1b1b2b8w1w12w1w1ww1w1w1w1w2w1w1w1w1ww1w1w1w1w1',  -- После хода 3
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b2b1b1b1b11w12b1w1w1ww1w1w1w1w2w1w1w1w1ww1w1w1w1w1',   -- После хода 4
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b2b1b1b1b11w3w10w1w1ww3w1w1w2w1w1w1w1ww1w1w1w1w1',       -- После хода 5
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b4b1b1b2b8w3w10w1w1ww3w1w1w2w1w1w1w1ww1w1w1w1w1',         -- После хода 6
        '1b1b1b1b1bb1b1b1b1b2b1b1b1b1b2w1b1b1b15w10w1w1ww3w1w1w2w1w1w1w1ww1w1w1w1w1',          -- После хода 7
        '1b1b1b1b1bb1b1b1b1b2b3b1b4b6b3w24w3w1w1w2w1w1w1w1ww1w1w1w1w1',                        -- После хода 8
        '1b1b1b1b1bb1b1b1b1b2b3b1b4b6b1w1w10w3w1w1w2w1w1w1w1ww1w1w1w1w1',                       -- После хода 9
        '1b1b1b1b1bb1b1b1b1b2b3b1b4b11b14b10w2w3w1w1w2w1w1w1w1ww1w1w1w1w1'                     -- После хода 10
    );
    
    -- Ходы (из реальной игры)
    TYPE move_array IS TABLE OF VARCHAR2(50);
    v_moves move_array := move_array(
        'b4-a5',      -- Ход 1
        'a7-b6',      -- Ход 2
        'd4-c5',      -- Ход 3
        'b6:d4',      -- Ход 4
        'c3:e5',      -- Ход 5
        'c7-b6',      -- Ход 6
        'a5:c7',      -- Ход 7
        'd8:b6',      -- Ход 8
        'e5-f6',      -- Ход 9
        'e7:g5'       -- Ход 10
    );
    
    -- Флаги взятия
    TYPE capture_array IS TABLE OF CHAR(1);
    v_captures capture_array := capture_array('N', 'N', 'N', 'Y', 'Y', 'N', 'Y', 'Y', 'N', 'Y');
    
    v_batch_size NUMBER := 1000; -- Размер пакета для коммита
    v_games_created NUMBER := 0;
    v_moves_created NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Начало создания тестовых данных...');
    DBMS_OUTPUT.PUT_LINE('Планируется создать: ' || v_total_games || ' игр, ' || (v_total_games * v_moves_per_game) || ' ходов');
    DBMS_OUTPUT.PUT_LINE('Размер пакета для коммита: ' || v_batch_size || ' игр');
    DBMS_OUTPUT.PUT_LINE('');
    
    v_start_time := SYSTIMESTAMP;
    
    -- Проверка существования игроков
    BEGIN
        SELECT player_id INTO v_player1_id FROM players WHERE player_id = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('ОШИБКА: Игрок с ID 1 не найден. Создайте игроков перед выполнением скрипта.');
            RETURN;
    END;
    
    BEGIN
        SELECT player_id INTO v_player2_id FROM players WHERE player_id = 2;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('ОШИБКА: Игрок с ID 2 не найден. Создайте игроков перед выполнением скрипта.');
            RETURN;
    END;
    
    -- Получить максимальный game_id
    SELECT NVL(MAX(game_id), 0) INTO v_game_id FROM games;
    
    -- Создание игр и ходов
    FOR i IN 1..v_total_games LOOP
        -- Создать игру
        v_game_id := v_game_id + 1;
        
        INSERT INTO games (
            game_id,
            player_white_id,
            player_black_id,
            rule_id,
            creator_player_color,
            status,
            current_turn,
            start_time,
            end_time,
            winner_player_color
        ) VALUES (
            v_game_id,
            v_player1_id,
            v_player2_id,
            v_rule_id,
            'W', -- Создатель (игрок на белых)
            'V', -- Завершена
            'B', -- Последний ход был черных
            SYSDATE - (v_total_games - i) / 86400, -- Распределить игры по времени
            SYSDATE - (v_total_games - i) / 86400 + INTERVAL '10' MINUTE,
            'B'  -- Победитель - черные
        );
        
        -- Создать ходы
        FOR j IN 1..v_moves_per_game LOOP
            v_move_number := j;
            
            INSERT INTO game_moves (
                game_id,
                move_number,
                move_notation,
                is_capture,
                board_position,
                move_timestamp
            ) VALUES (
                v_game_id,
                v_move_number,
                v_moves(j),
                v_captures(j),
                v_boards(j),
                SYSDATE - (v_total_games - i) / 86400 + (j * INTERVAL '1' MINUTE)
            );
            
            v_moves_created := v_moves_created + 1;
        END LOOP;
        
        v_games_created := v_games_created + 1;
        
        -- Коммит пакетами
        IF MOD(v_games_created, v_batch_size) = 0 THEN
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('Создано игр: ' || v_games_created || ' / ' || v_total_games || 
                               ' (ходов: ' || v_moves_created || ')');
        END IF;
    END LOOP;
    
    -- Финальный коммит
    COMMIT;
    
    v_end_time := SYSTIMESTAMP;
    v_elapsed_seconds := EXTRACT(SECOND FROM (v_end_time - v_start_time)) + 
                        EXTRACT(MINUTE FROM (v_end_time - v_start_time)) * 60 +
                        EXTRACT(HOUR FROM (v_end_time - v_start_time)) * 3600;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Готово!');
    DBMS_OUTPUT.PUT_LINE('Создано игр: ' || v_games_created);
    DBMS_OUTPUT.PUT_LINE('Создано ходов: ' || v_moves_created);
    DBMS_OUTPUT.PUT_LINE('Время выполнения: ' || ROUND(v_elapsed_seconds, 2) || ' секунд');
    DBMS_OUTPUT.PUT_LINE('Скорость: ' || ROUND(v_games_created / v_elapsed_seconds, 2) || ' игр/сек');
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ОШИБКА: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Создано игр: ' || v_games_created);
        DBMS_OUTPUT.PUT_LINE('Создано ходов: ' || v_moves_created);
        RAISE;
END;


-- -- Проверка результатов
-- SELECT 
--     COUNT(*) as total_games,
--     COUNT(DISTINCT game_id) as unique_games,
--     MIN(game_id) as min_game_id,
--     MAX(game_id) as max_game_id
-- FROM games
-- WHERE player_white_id = 1 AND player_black_id = 2;

-- SELECT 
--     COUNT(*) as total_moves,
--     COUNT(DISTINCT game_id) as games_with_moves,
--     AVG(move_number) as avg_moves_per_game
-- FROM game_moves
-- WHERE game_id IN (
--     SELECT game_id FROM games 
--     WHERE player_white_id = 1 AND player_black_id = 2
-- );

