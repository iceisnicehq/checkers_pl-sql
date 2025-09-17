SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- =================================================================
-- == ЭТАП 0: ПОДГОТОВКА (ОЧИСТКА)
-- =================================================================

DECLARE
BEGIN
    DELETE FROM C##CHECKERS_APP.game_moves;
    DELETE FROM C##CHECKERS_APP.games;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Таблицы game_moves и games очищены.');
END;

-- =================================================================
-- == ЭТАП 1: СОЗДАНИЕ И ПРИНЯТИЕ ВЫЗОВА
-- =================================================================

-- -----------------------------------------------------------------
-- ШАГ 1.1: C##DEV_USER создает ПРЯМОЙ вызов для C##DEV2_USER
-- -----------------------------------------------------------------
DECLARE
    v_game_id NUMBER;
    v_msg     VARCHAR2(1000);
BEGIN
    DBMS_OUTPUT.PUT_LINE('[TEST] C##DEV_USER создает прямой вызов для C##DEV2_USER...');
    C##CHECKERS_APP.game_logic.create_game(
        p_opponent_username => 'C##DEV2_USER',
        p_player_color      => 'W',
        p_game_id           => v_game_id,
        p_status_message    => v_msg
    );
    DBMS_OUTPUT.PUT_LINE(v_msg);
END;


-- -----------------------------------------------------------------
-- ШАГ 1.2: C##DEV2_USER принимает вызов
-- -----------------------------------------------------------------
DECLARE
    v_challenge_id NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('[TEST] C##DEV2_USER ищет и принимает вызов...');
    SELECT game_id INTO v_challenge_id
    FROM C##CHECKERS_APP.v_open_games
    WHERE challenged_player = USER AND ROWNUM = 1;
    DBMS_OUTPUT.PUT_LINE('[INFO] Найден вызов с ID: ' || v_challenge_id || '. Присоединяемся...');
    C##CHECKERS_APP.game_logic.join_game(p_game_id => v_challenge_id);
    DBMS_OUTPUT.PUT_LINE('[SUCCESS] Вызов принят! Партия теперь АКТИВНА.');
    DBMS_OUTPUT.PUT_LINE('[INFO] Текущее состояние доски:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_challenge_id));
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Прямых вызовов для ' || USER || ' не найдено!');
END;


-- =================================================================
-- == ЭТАП 2: ВЫПОЛНЕНИЕ ХОДОВ
-- =================================================================
-- -----------------------------------------------------------------
-- ШАГ 2.1: Ход Белых (C##DEV_USER)
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    v_game_id := C##CHECKERS_APP.game_logic.get_my_active_game();
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('--- ИГРА ' || v_game_id || ': Ход Белых (C##DEV_USER) ---');
        C##CHECKERS_APP.game_logic.make_move(
            p_game_id       => v_game_id,
            p_move_notation => 'c3-d4',
            p_status_message => v_status_message
        );
        DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после хода:');
        DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] Активных партий для ' || USER || ' не найдено.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;


-- -----------------------------------------------------------------
-- ШАГ 2.2: Ход Черных (C##DEV2_USER)
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    v_game_id := C##CHECKERS_APP.game_logic.get_my_active_game();
    IF v_game_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('--- ИГРА ' || v_game_id || ': Ход Черных (C##DEV2_USER) ---');
        C##CHECKERS_APP.game_logic.make_move(
            p_game_id       => v_game_id,
            p_move_notation => 'd6-c5',
            p_status_message => v_status_message
        );
        DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после хода:');
        DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
    ELSE
         DBMS_OUTPUT.PUT_LINE('[INFO] Активных партий для ' || USER || ' не найдено.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;