-- @function get_initial_position
-- @brief Returns the starting board position for a given game rule.
-- @dependencies:
--   - game_rules (table)
--   - p_audit_log (procedure)

FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
    v_rule      game_rules%ROWTYPE;
    v_error_msg VARCHAR2(200); -- Переменная для сообщения об ошибке
BEGIN
    -- Сначала пытаемся найти правило
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Обработка случая, если ID правила вообще не найден в таблице
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
            
            -- 1) Запись в аудит
            p_audit_log(
                p_player_id => NULL,
                p_game_id   => NULL,
                p_event_type => v_error_msg
            );
            
            -- 2) Вывод DBMS_OUTPUT
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            
            -- 3) Завершение функции
            RETURN NULL;
    END;

    -- [ИЗМЕНЕНИЕ] Правило найдено, проверяем РАЗМЕР ДОСКИ
    IF v_rule.board_size = 8 THEN
        -- 8x8 (Например, Русские шашки)
        RETURN '+b+b+b+b' || -- Row 8
            'b+b+b+b+' || -- Row 7
            '+b+b+b+b' || -- Row 6
            '++++++++' || -- Row 5
            '++++++++' || -- Row 4
            'w+w+w+w+' || -- Row 3
            '+w+w+w+w' || -- Row 2
            'w+w+w+w+';  -- Row 1 (Всего 64 символа)

    ELSIF v_rule.board_size = 10 THEN
        -- 10x10 (Например, Международные шашки)
        RETURN 'b+b+b+b+b' || -- Row 10
            '+b+b+b+b+b' || -- Row 9
            'b+b+b+b+b' || -- Row 8
            '+b+b+b+b+b' || -- Row 7
            '++++++++++' || -- Row 6
            '++++++++++' || -- Row 5
            'w+w+w+w+w' || -- Row 4
            '+w+w+w+w+w' || -- Row 3
            'w+w+w+w+w' || -- Row 2
            '+w+w+w+w+w'; -- Row 1 (Всего 100 символов)
    ELSE
        -- Неподдерживаемый размер
        v_error_msg := 'Правила игры с ID=' || p_rule_id || ' (Размер: ' || v_rule.board_size || ') не поддерживаются.';
        
        -- 1) Запись в аудит
        p_audit_log(
            p_player_id => NULL,
            p_game_id   => NULL,
            p_event_type => v_error_msg
        );
        
        -- 2) Вывод DBMS_OUTPUT
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        
        -- 3) Завершение функции
        RETURN NULL;
    END IF;
END get_initial_position;