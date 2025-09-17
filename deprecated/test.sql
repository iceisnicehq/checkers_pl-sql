-- =================================================================
-- Улучшенный тестовый скрипт для игры "Шашки"
-- =================================================================
-- Настройки для корректного вывода в SQL*Plus или SQL Developer
SET SERVEROUTPUT ON;
SET LONG 20000; -- Увеличиваем лимит вывода, чтобы CLOB не обрезался

DECLARE
    v_game_id NUMBER;
    v_board   CLOB;
BEGIN
    -- 1. ПОПЫТКА СОЗДАТЬ ИГРУ
    -- Этот блок позволяет запускать скрипт многократно.
    -- Если игра еще не создана, он ее создаст.
    -- Если игра уже есть, он не упадет с ошибкой, а просто найдет ID существующей партии.
    BEGIN
        game_logic.create_game(
            p_opponent_username => 'PLAYER2', -- Укажите имя вашего оппонента
            p_game_id           => v_game_id
        );
        DBMS_OUTPUT.PUT_LINE('Успешно создана новая партия с ID: ' || v_game_id);
    EXCEPTION
        WHEN game_logic.e_player_is_busy THEN
            -- Если игроки уже в игре, просто получаем ID их активной партии
            SELECT g.game_id INTO v_game_id
            FROM games g
            JOIN players p1 ON g.player_white_id = p1.player_id OR g.player_black_id = p1.player_id
            WHERE g.status = 'ACTIVE' AND p1.username = USER;

            DBMS_OUTPUT.PUT_LINE('Игроки уже в игре. Используем активную партию с ID: ' || v_game_id);
    END;


    -- 2. ПОЛУЧЕНИЕ И ВЫВОД ПОЛНОЙ ИНФОРМАЦИИ О ПАРТИИ
    IF v_game_id IS NOT NULL THEN
        -- Получаем красивое представление доски с помощью нашей новой функции
        v_board := game_logic.get_printable_board(v_game_id);

        -- Выводим дополнительную информацию для контекста
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- Текущий статус партии ---');

        FOR r_game IN (
            SELECT
                g.status,
                g.current_turn,
                pw.username as white_player,
                pb.username as black_player
            FROM games g
            JOIN players pw ON g.player_white_id = pw.player_id
            JOIN players pb ON g.player_black_id = pb.player_id
            WHERE g.game_id = v_game_id
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('Игроки: ' || r_game.white_player || ' (Белые) vs ' || r_game.black_player || ' (Черные)');
            DBMS_OUTPUT.PUT_LINE('Статус: ' || r_game.status);
            DBMS_OUTPUT.PUT_LINE('Ход: '    || CASE r_game.current_turn WHEN 'W' THEN 'Белых' ELSE 'Черных' END);
        END LOOP;

        -- Выводим саму доску
        DBMS_OUTPUT.PUT_LINE(v_board);
    ELSE
        DBMS_OUTPUT.PUT_LINE('Не удалось найти или создать партию.');
    END IF;

END;
/