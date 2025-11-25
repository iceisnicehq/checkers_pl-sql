-- @procedure p_init_board_map
-- @brief Initializes global cache maps for board coordinates (Index <-> Notation).
-- @dependencies: global variables g_map_by_notation, g_map_by_idx, g_current_map_size

PROCEDURE p_init_board_map(p_board_size IN NUMBER) IS
    v_idx       PLS_INTEGER;
    v_notation  VARCHAR2(10); -- Увеличено до 10 для поддержки нотаций типа 'j10' для досок 10x10
    v_field_rec rec_board_field;
BEGIN
    -- 1. Проверяем кэш. Если карта нужного размера уже загружена, выходим.
    IF p_board_size = g_current_map_size THEN
        RETURN;
    END IF;
    
    -- 2. Очищаем старые карты
    g_map_by_notation.DELETE;
    g_map_by_idx.DELETE;
    
    -- 3. Генерируем новые карты
    FOR r IN 1 .. p_board_size LOOP
        FOR c IN 1 .. p_board_size LOOP
            -- Формула индекса: Сверху-вниз (строка 1 в строке = 8/10 ряд на доске)
            -- Нотация 'a1' находится в конце строки (для 8x8 это индекс 57..64)
            v_idx := ((p_board_size - r) * p_board_size) + c;
            
            -- Нотация (например, 'a1', 'h8', 'j10')
            -- ASCII('a') = 97. Для c=1 -> 'a', c=8 -> 'h', c=10 -> 'j'.
            v_notation := CHR(ASCII('a') + c - 1) || r;

            -- Собираем запись
            v_field_rec.idx      := v_idx;
            v_field_rec.notation := v_notation;
            v_field_rec.row_num  := r;
            v_field_rec.col_num  := c;

            -- Заполняем ОБЕ карты
            g_map_by_notation(v_notation) := v_field_rec;
            g_map_by_idx(v_idx)           := v_field_rec;
            
        END LOOP;
    END LOOP;
    
    -- 4. Обновляем "флаг" кэша
    g_current_map_size := p_board_size;
    
END p_init_board_map;