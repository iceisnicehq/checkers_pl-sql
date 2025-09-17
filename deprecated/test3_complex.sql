-- =================================================================
-- == НОВЫЙ ТЕСТОВЫЙ СЦЕНАРИЙ (Версия для правила 1 сессии) ==
-- =================================================================
SET SERVEROUTPUT ON;
SET LONG 20000;
SET DEFINE OFF;
-- ШАГ 0: Полная очистка
-- Подключитесь как C##CHECKERS_APP и выполните этот блок.
PROMPT [INFO] Performing cleanup...
DELETE FROM C##CHECKERS_APP.game_moves;
DELETE FROM C##CHECKERS_APP.games;
COMMIT;
PROMPT [INFO] Cleanup complete.
-- СЦЕНАРИЙ 1: Проверка правила "ОДНА СЕССИЯ"
PROMPT --- СЦЕНАРИЙ 1: Проверка правила "ОДНА СЕССИЯ" ---
-- 1.1: C##DEV_USER успешно создает первую игру
-- Подключитесь как C##DEV_USER
DECLARE
v_game_id NUMBER;
v_msg VARCHAR2(1000);
BEGIN
DBMS_OUTPUT.PUT_LINE('[TEST 1.1] C##DEV_USER создает первую игру...');
C##CHECKERS_APP.game_logic.create_game(p_game_id => v_game_id, p_status_message => v_msg);
DBMS_OUTPUT.PUT_LINE(v_msg);
END;
/
-- 1.2: C##DEV_USER НЕ МОЖЕТ создать вторую игру
-- Подключитесь как C##DEV_USER
DECLARE
v_game_id NUMBER;
v_msg VARCHAR2(1000);
BEGIN
DBMS_OUTPUT.PUT_LINE(CHR(10) || '[TEST 1.2] C##DEV_USER пытается создать вторую игру (ожидается ошибка)...');
C##CHECKERS_APP.game_logic.create_game(p_game_id => v_game_id, p_status_message => v_msg);
EXCEPTION
WHEN OTHERS THEN
IF SQLCODE = -20001 THEN
DBMS_OUTPUT.PUT_LINE('[SUCCESS] Ошибка "e_player_is_busy" успешно перехвачена. Правило работает!');
ELSE
RAISE;
END IF;
END;
/
-- СЦЕНАРИЙ 2: Проверка УВЕДОМЛЕНИЙ
PROMPT --- СЦЕНАРИЙ 2: Проверка УВЕДОМЛЕНИЙ ---
-- Для этого сценария нам понадобится третий пользователь, C##DEV3_USER.
-- Убедитесь, что он создан и имеет права CONNECT.
-- 2.1: C##DEV2_USER бросает прямой вызов C##DEV_USER
-- Подключитесь как C##DEV2_USER
DECLARE
v_game_id NUMBER;
v_msg VARCHAR2(1000);
BEGIN
DBMS_OUTPUT.PUT_LINE(CHR(10) || '[TEST 2.1] C##DEV2_USER вызывает C##DEV_USER...');
C##CHECKERS_APP.game_logic.create_game(p_opponent_username => 'C##DEV_USER', p_game_id => v_game_id, p_status_message => v_msg);
DBMS_OUTPUT.PUT_LINE(v_msg);
END;
/
-- 2.2: C##DEV3_USER создает открытую игру (для статистики)
-- Подключитесь как C##DEV3_USER
DECLARE
v_game_id NUMBER;
v_msg VARCHAR2(1000);
BEGIN
DBMS_OUTPUT.PUT_LINE(CHR(10) || '[TEST 2.2] C##DEV3_USER создает открытую игру...');
C##CHECKERS_APP.game_logic.create_game(p_game_id => v_game_id, p_status_message => v_msg);
DBMS_OUTPUT.PUT_LINE(v_msg);
END;
/
-- 2.3: C##DEV_USER (которого ждут) создает свою игру и получает уведомления
-- Подключитесь как C##DEV_USER
DECLARE
v_game_id NUMBER;
v_msg VARCHAR2(1000);
BEGIN
DBMS_OUTPUT.PUT_LINE(CHR(10) || '[TEST 2.3] C##DEV_USER создает свою игру и должен увидеть уведомления...');
C##CHECKERS_APP.game_logic.create_game(p_game_id => v_game_id, p_status_message => v_msg);
DBMS_OUTPUT.PUT_LINE('--- ПОЛУЧЕННОЕ СООБЩЕНИЕ ---');
DBMS_OUTPUT.PUT_LINE(v_msg);
DBMS_OUTPUT.PUT_LINE('-----------------------------');
DBMS_OUTPUT.PUT_LINE('[VERIFY] Проверьте, что в сообщении есть вызов от C##DEV2_USER и упоминание 1 другой открытой игры.');
END;
/