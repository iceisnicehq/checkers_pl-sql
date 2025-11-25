FUNCTION get_initial_position(p_rule_id IN NUMBER) RETURN VARCHAR2 IS
    v_rule      game_rules%ROWTYPE;
    v_error_msg VARCHAR2(255); 
BEGIN
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_error_msg := 'Правила игры с ID=' || p_rule_id || ' не найдены.';
            p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_msg => v_error_msg);
            DBMS_OUTPUT.PUT_LINE(v_error_msg);
            RETURN NULL;
    END;

    IF v_rule.board_size = 8 THEN
        RETURN '+b+b+b+b' ||
               'b+b+b+b+' ||
               '+b+b+b+b' ||
               '++++++++' ||
               '++++++++' ||
               'w+w+w+w+' ||
               '+w+w+w+w' ||
               'w+w+w+w+';

    ELSIF v_rule.board_size = 10 THEN
        RETURN '+b+b+b+b+b' ||
               'b+b+b+b+b+' ||
               '+b+b+b+b+b' ||
               'b+b+b+b+b+' ||
               '++++++++++' ||
               '++++++++++' ||
               '+w+w+w+w+w' ||
               'w+w+w+w+w+' ||
               '+w+w+w+w+w' ||
               'w+w+w+w+w+';
    ELSE
        v_error_msg := 'Правила с ID=' || p_rule_id || ' (Размер: ' || v_rule.board_size || ') не поддерживаются.';
        p_audit_log(p_player_id => NULL, p_game_id => NULL, p_event_msg => v_error_msg);
        DBMS_OUTPUT.PUT_LINE(v_error_msg);
        RETURN NULL;
    END IF;
END get_initial_position;
