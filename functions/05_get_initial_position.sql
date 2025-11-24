-- @function get_initial_position
-- @brief Returns the starting board position string based on rules.

FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
    v_rule      game_rules%ROWTYPE;
    v_error_msg VARCHAR2(255); 
BEGIN
    -- Сначала пытаемся найти правило
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
            p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_type => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN NULL;
    END;

    -- Проверяем РАЗМЕР ДОСКИ
    IF v_rule.board_size = 8 THEN
        -- 8x8 (Русские шашки: 64 символа)
        RETURN '+b+b+b+b' || -- Row 8
               'b+b+b+b+' || -- Row 7
               '+b+b+b+b' || -- Row 6
               '++++++++' || -- Row 5
               '++++++++' || -- Row 4
               'w+w+w+w+' || -- Row 3
               '+w+w+w+w' || -- Row 2
               'w+w+w+w+';   -- Row 1

    ELSIF v_rule.board_size = 10 THEN
        -- 10x10 (Международные шашки: 100 символов)
        RETURN 'b+b+b+b+b' || -- Row 10
               '+b+b+b+b+b' || -- Row 9
               'b+b+b+b+b' || -- Row 8
               '+b+b+b+b+b' || -- Row 7
               '++++++++++' || -- Row 6
               '++++++++++' || -- Row 5
               'w+w+w+w+w' || -- Row 4
               '+w+w+w+w+w' || -- Row 3
               'w+w+w+w+w' || -- Row 2
               '+w+w+w+w+w';   -- Row 1
    ELSE
        -- Неподдерживаемый размер
        v_error_msg := 'Правила с ID=' || p_rule_id || ' (Размер: ' || v_rule.board_size || ') не поддерживаются.';
        p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_type => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN NULL;
    END IF;
END get_initial_position;