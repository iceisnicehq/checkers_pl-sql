SET SERVEROUTPUT ON;

DECLARE
    v_current_month DATE := TRUNC(SYSDATE, 'MM');
    v_next_month DATE := ADD_MONTHS(v_current_month, 1);
    v_season_name VARCHAR2(100);
    v_month_names SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
        'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    );
    v_month_num PLS_INTEGER;
    v_year_num PLS_INTEGER;
    v_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM seasons
    WHERE start_date <= v_current_month
      AND end_date >= v_current_month;
    
    IF v_count = 0 THEN
        v_month_num := EXTRACT(MONTH FROM v_current_month);
        v_year_num := EXTRACT(YEAR FROM v_current_month);
        v_season_name := v_month_names(v_month_num) || '-' || v_year_num;
        
        INSERT INTO seasons (season_name, start_date, end_date)
        VALUES (v_season_name, v_current_month, v_next_month - 1);
        
        COMMIT;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Сезон не создан: ' || SQLERRM);
END;

