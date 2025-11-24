-- @procedure p_init_board_map
-- @brief Initializes or rebuilds the global board maps (g_map_by_notation, g_map_by_idx).
-- @dependencies:
--   - g_map_by_notation, g_map_by_idx, g_current_map_size (global variables)
--   - rec_board_field (type)

PROCEDURE p_init_board_map(p_board_size IN NUMBER) IS
    v_idx       PLS_INTEGER;
    v_notation  VARCHAR2(10);
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
            v_idx := ((p_board_size - r) * p_board_size) + c;
            
            -- Нотация (например, 'a1', 'h8', 'j10')
            v_notation := CHR(ASCII('a') + c - 1);
            IF c > 8 THEN -- Для 10x10 (i, j)
               v_notation := CHR(ASCII('a') + c - 1);
            END IF;
            v_notation := v_notation || r;

            -- Собираем запись
            v_field_rec.idx        := v_idx;
            v_field_rec.notation   := v_notation;
            v_field_rec.row_num    := r;
            v_field_rec.col_num    := c;

            -- Заполняем ОБЕ карты
            g_map_by_notation(v_notation) := v_field_rec;
            g_map_by_idx(v_idx)           := v_field_rec;
            
        END LOOP;
    END LOOP;
    
    -- 4. Обновляем "флаг" кэша
    g_current_map_size := p_board_size;
    
END p_init_board_map;