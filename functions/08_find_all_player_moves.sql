-- @function find_all_player_moves
-- @brief Finds all legal moves for a given player.
-- @dependencies:
--   - decode_board (function)
--   - find_capture_paths (function)
--   - p_init_board_map (procedure)
--   - p_audit_log (procedure)
--   - game_rules (table)
--   - c_white_man, c_white_king, c_black_man, c_black_king, c_empty_field (constants)
--   - g_map_by_idx (global variable)
--   - t_move_list, r_move, r_move_step, rec_board_field (types)

FUNCTION find_all_player_moves(
    p_board        IN VARCHAR2,
    p_player_color IN CHAR,
    p_rule_id      IN NUMBER
) RETURN t_move_list IS
    v_all_moves       t_move_list := t_move_list();
    v_capture_moves   t_move_list := t_move_list();
    v_simple_moves    t_move_list := t_move_list();
    v_player_man      CHAR(1);
    v_player_king     CHAR(1);
    v_max_captures    PLS_INTEGER := 0;
    v_decoded_board   VARCHAR2(128) := decode_board(p_board); -- Max 128
    
    v_rule            game_rules%ROWTYPE;
    v_board_size      PLS_INTEGER;
    v_total_squares   PLS_INTEGER;
    v_simple_move_w   SYS.ODCINUMBERLIST;
    v_simple_move_b   SYS.ODCINUMBERLIST;
    v_simple_move_all SYS.ODCINUMBERLIST;
    v_max_king_range  PLS_INTEGER;

BEGIN
    -- 1. Настройка параметров
    BEGIN
        SELECT * INTO v_rule FROM game_rules WHERE rule_id = p_rule_id;
        v_board_size      := v_rule.board_size;
        v_total_squares   := v_board_size * v_board_size;
        v_max_king_range  := v_board_size - 1;
        
        p_init_board_map(v_board_size);
        
        IF v_board_size = 8 THEN
            v_simple_move_w   := SYS.ODCINUMBERLIST(-9, -7);
            v_simple_move_b   := SYS.ODCINUMBERLIST(7, 9);
            v_simple_move_all := SYS.ODCINUMBERLIST(-9, -7, 7, 9);
        ELSE -- 10x10
            v_simple_move_w   := SYS.ODCINUMBERLIST(-11, -9);
            v_simple_move_b   := SYS.ODCINUMBERLIST(9, 11);
            v_simple_move_all := SYS.ODCINUMBERLIST(-11, -9, 9, 11);
        END IF;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_audit_log(NULL, NULL, 'find_all_player_moves: Rule ' || p_rule_id || ' not found.');
            RETURN v_all_moves;
    END;

    IF p_player_color = 'W' THEN
        v_player_man  := c_white_man;
        v_player_king := c_white_king;
    ELSE
        v_player_man  := c_black_man;
        v_player_king := c_black_king;
    END IF;
    
    -- === 1. ПОИСК ВЗЯТИЙ (Captures) ===
    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece   CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_paths   t_move_list;
            v_is_king CHAR(1);
        BEGIN
            IF v_piece IN (v_player_man, v_player_king) THEN
                v_is_king := CASE WHEN v_piece IN (c_white_king, c_black_king) THEN 'Y' ELSE 'N' END;
                
                v_paths := find_capture_paths(i, v_decoded_board, p_player_color, v_is_king, p_rule_id);
                
                IF v_paths.COUNT > 0 THEN
                    FOR j IN 1 .. v_paths.COUNT LOOP
                        v_capture_moves.EXTEND;
                        v_capture_moves(v_capture_moves.LAST) := v_paths(j);
                        IF v_paths(j).capture_count > v_max_captures THEN
                            v_max_captures := v_paths(j).capture_count;
                        END IF;
                    END LOOP;
                END IF;
            END IF;
        END;
    END LOOP;

    -- === 2. ФИЛЬТРАЦИЯ ВЗЯТИЙ ===
    IF v_capture_moves.COUNT > 0 THEN
        -- Правило 1 (Русские): Обязательно бить, но можно выбрать ЛЮБОЕ количество
        IF p_rule_id = 1 THEN 
            RETURN v_capture_moves;
        ELSE 
        -- Правило 2 (Международные): Обязательно бить МАКСИМАЛЬНОЕ количество
            FOR i IN 1 .. v_capture_moves.COUNT LOOP
                IF v_capture_moves(i).capture_count = v_max_captures THEN
                    v_all_moves.EXTEND;
                    v_all_moves(v_all_moves.LAST) := v_capture_moves(i);
                END IF;
            END LOOP;
            RETURN v_all_moves;
        END IF;
    END IF;

    -- === 3. ПОИСК "ТИХИХ" ХОДОВ (Simple moves) ===
    FOR i IN 1 .. v_total_squares LOOP
        DECLARE
            v_piece       CHAR(1) := SUBSTR(v_decoded_board, i, 1);
            v_start_field rec_board_field := g_map_by_idx(i); 
        BEGIN
            IF v_piece = v_player_man THEN
                DECLARE
                    v_directions SYS.ODCINUMBERLIST;
                BEGIN
                    IF p_player_color = 'W' THEN v_directions := v_simple_move_w;
                    ELSE v_directions := v_simple_move_b; END IF;
                    
                    FOR d IN 1 .. v_directions.COUNT LOOP
                        DECLARE
                            v_end_idx   PLS_INTEGER := i + v_directions(d);
                            v_end_field rec_board_field;
                        BEGIN
                            -- Проверяем границы и пустоту клетки
                            IF v_end_idx BETWEEN 1 AND v_total_squares 
                               AND g_map_by_idx.EXISTS(v_end_idx) 
                               AND SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field 
                            THEN
                                v_end_field := g_map_by_idx(v_end_idx);
                                -- Простая шашка ходит только на соседнюю клетку (разница колонок = 1)
                                IF ABS(v_start_field.col_num - v_end_field.col_num) = 1 THEN
                                    DECLARE
                                        v_move r_move;
                                        v_step r_move_step;
                                    BEGIN
                                        v_step.start_idx     := i;
                                        v_step.end_idx       := v_end_idx;
                                        v_step.captured_idx  := NULL;
                                        v_move.path          := t_move_path(v_step);
                                        v_move.is_capture    := 'N';
                                        v_move.capture_count := 0;
                                        v_simple_moves.EXTEND;
                                        v_simple_moves(v_simple_moves.LAST) := v_move;
                                    END;
                                END IF;
                            END IF;
                        END;
                    END LOOP;
                END;
                
            ELSIF v_piece = v_player_king THEN
                DECLARE
                    v_directions SYS.ODCINUMBERLIST := v_simple_move_all;
                BEGIN
                    FOR d IN 1 .. v_directions.COUNT LOOP
                        FOR k IN 1 .. v_max_king_range LOOP 
                            DECLARE
                                v_end_idx   PLS_INTEGER := i + (v_directions(d) * k);
                                v_end_field rec_board_field;
                            BEGIN
                                IF NOT g_map_by_idx.EXISTS(v_end_idx) THEN EXIT; END IF;
                                v_end_field := g_map_by_idx(v_end_idx);
                                
                                -- Проверка геометрии (чтобы не перепрыгнуть через край на другую строку)
                                -- Если это не первый шаг, проверяем связность с предыдущей клеткой
                                IF k > 1 AND ABS(g_map_by_idx(i + (v_directions(d) * (k - 1))).col_num - v_end_field.col_num) != 1 THEN
                                    EXIT;
                                END IF;

                                IF SUBSTR(v_decoded_board, v_end_idx, 1) = c_empty_field THEN
                                    DECLARE
                                        v_move r_move;
                                        v_step r_move_step;
                                    BEGIN
                                        v_step.start_idx     := i;
                                        v_step.end_idx       := v_end_idx;
                                        v_step.captured_idx  := NULL;
                                        v_move.path          := t_move_path(v_step);
                                        v_move.is_capture    := 'N';
                                        v_move.capture_count := 0;
                                        v_simple_moves.EXTEND;
                                        v_simple_moves(v_simple_moves.LAST) := v_move;
                                    END;
                                ELSE
                                    EXIT; -- Клетка занята, дальше идти нельзя
                                END IF;
                            END;
                        END LOOP;
                    END LOOP;
                END;
            END IF;
        END;
    END LOOP;

    RETURN v_simple_moves;
END find_all_player_moves;