SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- =================================================================
-- Примечание: Этот блок очищает ВСЕ игры. Запускайте с осторожностью.
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Таблицы game_moves и games очищены.');
END;
/

-- =================================================================
-- == ЭТАП 1: СОЗДАНИЕ И ПРИНЯТИЕ ВЫЗОВА (КАК БЫЛО У ВАС)
-- =================================================================
-- Предполагается, что следующие два блока выполняются из разных сессий
-- (один под C##DEV_USER, другой под C##DEV2_USER)
-- или последовательно одним пользователем, который имеет права на этих юзеров.

-- -----------------------------------------------------------------
-- ШАГ 1.1: C##DEV_USER создает ПРЯМОЙ вызов для C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
    v_msg     VARCHAR2(1000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.1: C##DEV_USER создает вызов ---');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color      => 'W',
        p_game_id           => v_game_id,
        p_status_message    => v_msg
    );
    DBMS_OUTPUT.PUT_LINE(v_msg);
END;
/

-- -----------------------------------------------------------------
-- ШАГ 1.2: C##DEV2_USER принимает вызов
-- -----------------------------------------------------------------
DECLARE
    v_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 1.2: C##DEV2_USER принимает вызов ---');
    SELECT game_id INTO v_challenge_id
    FROM C##CHECKERS_APP.v_open_games
    WHERE challenged_player = 'C##DEV2_USER' AND ROWNUM = 1; -- USER заменен на конкретное имя для универсальности скрипта
    DBMS_OUTPUT.PUT_LINE('[INFO] Найден вызов с ID: ' || v_challenge_id || '. Присоединяемся...');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Вызов принят! Партия теперь АКТИВНА.');
    DBMS_OUTPUT.PUT_LINE('[INFO] Текущее состояние доски:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_challenge_id));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Прямых вызовов для C##DEV2_USER не найдено!');
END;
/

-- =================================================================
-- == ЭТАП 2: ВЫПОЛНЕНИЕ ПРОСТЫХ ХОДОВ
-- =================================================================
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    -- Получаем ID игры между DEV_USER и DEV2_USER
    SELECT game_id INTO v_game_id FROM games
    WHERE status = 'ACTIVE' AND ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.1: Ход Белых (c3-d4) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'c3-d4', v_status_message);
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 2.2: Ход Черных (d6-c5) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'd6-c5', v_status_message);
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после простых ходов:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
END;
/

-- =================================================================
-- == ЭТАП 3: ТЕСТИРОВАНИЕ ОБЯЗАТЕЛЬНОГО ВЗЯТИЯ
-- =================================================================
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    SELECT game_id INTO v_game_id FROM games WHERE status = 'ACTIVE' AND ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.1: Белые создают ситуацию для взятия (d4-e5) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'd4-e5', v_status_message);
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    DBMS_OUTPUT.PUT_LINE('Доска теперь:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.2: Черные ПЫТАЮТСЯ сделать простой ход (h6-g5) ---');
    BEGIN
        C##CHECKERS_APP.game_logic.make_move(v_game_id, 'h6-g5', v_status_message);
        DBMS_OUTPUT.PUT_LINE('[FAIL] Система позволила сделать неверный ход!');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20007 THEN
                DBMS_OUTPUT.PUT_LINE('[SUCCESS] Система правильно запретила ход. Ошибка: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('[FAIL] Неожиданная ошибка: ' || SQLERRM);
            END IF;
    END;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 3.3: Черные делают ПРАВИЛЬНЫЙ ход со взятием (f6:d4) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'f6:d4', v_status_message);
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    DBMS_OUTPUT.PUT_LINE('Доска после взятия:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
END;
/

-- =================================================================
-- == ЭТАП 4: ТЕСТИРОВАНИЕ МНОГОКРАТНОГО ВЗЯТИЯ И ПРАВИЛА МАКСИМУМА
-- =================================================================
DECLARE
    v_game_id        NUMBER;
    v_msg            VARCHAR2(1000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4: Создание новой игры для теста многократного взятия ---');
    -- Создаем игру между новыми игроками
    C##CHECKERS_APP.game_logic.create_game('C##DEV4_USER', 'W', 1, NULL, NULL, v_game_id, v_msg);
    C##CHECKERS_APP.game_logic.join_game(v_game_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Создана и начата новая игра с ID: ' || v_game_id);

    -- Создаем позицию для теста
    DBMS_OUTPUT.PUT_LINE('[INFO] Расставляем фигуры для теста...');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'c3-d4', v_msg); -- W
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'f6-e5', v_msg); -- B
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'b2-c3', v_msg); -- W
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'g7-f6', v_msg); -- B
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'g1-h2', v_msg); -- W
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'e7-d6', v_msg); -- B
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'd2-e3', v_msg); -- W
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'e5-g3', v_msg); -- B (создает 2 варианта взятия для белых)
    DBMS_OUTPUT.PUT_LINE('Доска готова к тесту. У белых есть выбор: взять одну (c3:e5) или две (h2:f4:d4)');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.1: Белые ПЫТАЮТСЯ выбрать короткий маршрут (c3:e5) ---');
    BEGIN
        C##CHECKERS_APP.game_logic.make_move(v_game_id, 'c3:e5', v_msg);
        DBMS_OUTPUT.PUT_LINE('[FAIL] Система позволила выбрать короткий маршрут взятия!');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20007 THEN
                DBMS_OUTPUT.PUT_LINE('[SUCCESS] Система правильно запретила ход (правило максимума). Ошибка: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('[FAIL] Неожиданная ошибка: ' || SQLERRM);
            END IF;
    END;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 4.2: Белые делают ПРАВИЛЬНЫЙ ход с максимальным взятием (h2:f4:d4) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'h2:f4:d4', v_msg);
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_msg);
    DBMS_OUTPUT.PUT_LINE('Доска после многократного взятия:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
END;
/

-- =================================================================
-- == ЭТАП 5: ТЕСТИРОВАНИЕ ЗАВЕРШЕНИЯ ИГРЫ (ПАТ)
-- =================================================================
DECLARE
    v_game_id        NUMBER;
    v_msg            VARCHAR2(1000);
    v_final_status   VARCHAR2(20);
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 5: Создание новой игры для теста на ПАТ ---');
    C##CHECKERS_APP.game_logic.create_game('C##DEV2_USER', 'W', 1, NULL, NULL, v_game_id, v_msg);
    C##CHECKERS_APP.game_logic.join_game(v_game_id);
    DBMS_OUTPUT.PUT_LINE('[OK] Создана и начата новая игра с ID: ' || v_game_id);

    -- Форсируем позицию, где у черных не будет ходов
    -- Для этого нужно очистить доску и расставить фигуры вручную через UPDATE
    -- Это приемлемо для юнит-теста.
    UPDATE C##CHECKERS_APP.games
    SET board_position = '___________________________b_w___', -- Черная на a1, белая на c1
        current_turn = 'B' -- Ход черных
    WHERE game_id = v_game_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[INFO] Позиция для пата установлена. Ход черных.');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ЭТАП 5.1: Черные пытаются сделать любой ход (например, a1-b2) ---');
    C##CHECKERS_APP.game_logic.make_move(v_game_id, 'a1-b2', v_msg);
    DBMS_OUTPUT.PUT_LINE('[INFO] ' || v_msg);

    -- Проверяем, что игра завершилась победой белых
    SELECT status INTO v_final_status FROM C##CHECKERS_APP.games WHERE game_id = v_game_id;
    IF v_final_status = 'WHITE_WIN' THEN
        DBMS_OUTPUT.PUT_LINE('[SUCCESS] Игра корректно завершилась патом. Статус: ' || v_final_status);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[FAIL] Игра не завершилась патом. Статус: ' || v_final_status);
    END IF;
END;
/