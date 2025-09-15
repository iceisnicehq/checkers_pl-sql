-- =================================================================
-- ==             ТЕСТОВЫЙ СКРИПТ ДЛЯ ВЫПОЛНЕНИЯ ХОДОВ             ==
-- =================================================================
SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;

-- -----------------------------------------------------------------
-- ШАГ 1: Ход Белых (C##DEV_USER)
-- Подключитесь как C##DEV_USER и выполните этот блок.
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    -- Находим активную партию текущего пользователя
    SELECT g.game_id INTO v_game_id FROM C##CHECKERS_APP.games g
    WHERE g.status = 'ACTIVE'
      AND (g.player_white_id = (SELECT player_id FROM C##CHECKERS_APP.players p WHERE p.username = USER)
        OR g.player_black_id = (SELECT player_id FROM C##CHECKERS_APP.players p WHERE p.username = USER));

    DBMS_OUTPUT.PUT_LINE('--- ИГРА ' || v_game_id || ': Ход Белых (C##DEV_USER) ---');
    DBMS_OUTPUT.PUT_LINE('Доска до хода:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

    -- === ВАШ ХОД ЗДЕСЬ ===
    C##CHECKERS_APP.game_logic.make_move(
        p_game_id       => v_game_id,
        p_move_notation => 'c3-d4',
        p_status_message => v_status_message
    );
    
    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после хода:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Активная партия для ' || USER || ' не найдена.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/


-- -----------------------------------------------------------------
-- ШАГ 2: Ход Черных (C##DEV2_USER)
-- Подключитесь как C##DEV2_USER и выполните этот блок.
-- -----------------------------------------------------------------
DECLARE
    v_game_id        NUMBER;
    v_status_message VARCHAR2(200);
BEGIN
    -- Находим активную партию текущего пользователя
    SELECT g.game_id INTO v_game_id FROM C##CHECKERS_APP.games g
    WHERE g.status = 'ACTIVE'
      AND (g.player_white_id = (SELECT player_id FROM C##CHECKERS_APP.players p WHERE p.username = USER)
        OR g.player_black_id = (SELECT player_id FROM C##CHECKERS_APP.players p WHERE p.username = USER));

    DBMS_OUTPUT.PUT_LINE('--- ИГРА ' || v_game_id || ': Ход Черных (C##DEV2_USER) ---');
    DBMS_OUTPUT.PUT_LINE('Доска до хода:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

    -- === ВАШ ХОД ЗДЕСЬ ===
    C##CHECKERS_APP.game_logic.make_move(
        p_game_id       => v_game_id,
        p_move_notation => 'd6-c5',
        p_status_message => v_status_message
    );

    DBMS_OUTPUT.PUT_LINE('[OK] ' || v_status_message);
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Доска после хода:');
    DBMS_OUTPUT.PUT_LINE(C##CHECKERS_APP.game_logic.get_printable_board(v_game_id));

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Активная партия для ' || USER || ' не найдена.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
END;
/