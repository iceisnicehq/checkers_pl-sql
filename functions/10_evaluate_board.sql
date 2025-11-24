-- @function evaluate_board
-- @brief Assigns a numerical score to a given board position.
-- @dependencies:
--   - p_init_board_map (procedure)
--   - c_empty_field (constant)
--   - g_map_by_idx (global variable)
--   - rec_board_field (type)

FUNCTION evaluate_board(
    p_board      IN VARCHAR2,
    p_ai_color   IN CHAR,
    p_difficulty IN NUMBER
) RETURN NUMBER IS
    v_score          NUMBER := 0;
    v_piece          CHAR(1);
    
    v_total_squares  PLS_INTEGER;
    v_board_size     PLS_INTEGER;
    
    c_man_value      CONSTANT NUMBER := 10;
    c_king_value     CONSTANT NUMBER := 50;
    c_side_val       CONSTANT NUMBER := 20; 
    c_wall_val       CONSTANT NUMBER := 10; 
    
    -- Переменные для проверки условия победы
    v_ai_pieces_cnt  PLS_INTEGER := 0;
    v_opp_pieces_cnt PLS_INTEGER := 0;

BEGIN
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    
    p_init_board_map(v_board_size);

    FOR i IN 1..v_total_squares LOOP
        v_piece := SUBSTR(p_board, i, 1);
        
        IF v_piece != c_empty_field THEN
            DECLARE
                v_piece_value    NUMBER;
                v_multiplier     NUMBER;
                v_piece_color    CHAR(1);
                
                v_field_rec      rec_board_field := g_map_by_idx(i);
                v_row            PLS_INTEGER     := v_field_rec.row_num;
                v_col            PLS_INTEGER     := v_field_rec.col_num;
                
                v_position_bonus NUMBER := 0;
            BEGIN
                -- Определяем цвет
                v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                
                -- Считаем фигуры для проверки конца игры
                IF v_piece_color = p_ai_color THEN
                    v_ai_pieces_cnt := v_ai_pieces_cnt + 1;
                ELSE
                    v_opp_pieces_cnt := v_opp_pieces_cnt + 1;
                END IF;

                -- Оценка материала
                v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                
                v_score := v_score + (v_piece_value * v_multiplier);

                -- Позиционные бонусы (только для Easy/Medium, на Hard чистый перебор)
                IF p_difficulty < 2 THEN
                    -- Бонус за борт
                    IF v_col = 1 OR v_col = v_board_size THEN
                        v_position_bonus := v_position_bonus + c_side_val;
                    END IF;

                    -- Бонус за продвижение
                    IF v_piece_color = 'W' THEN
                        v_position_bonus := v_position_bonus + ( (v_row / v_board_size) * c_wall_val );
                    ELSE -- Piece is Black
                        v_position_bonus := v_position_bonus + ( (( (v_board_size + 1) - v_row) / v_board_size) * c_wall_val );
                    END IF;
                END IF;
                
                v_score := v_score + (v_position_bonus * v_multiplier);
            END;
        END IF;
    END LOOP;
    
    -- Проверка терминального состояния (Победа/Поражение)
    IF v_ai_pieces_cnt > 0 AND v_opp_pieces_cnt = 0 THEN
        RETURN 9999; -- AI has won
    ELSIF v_ai_pieces_cnt = 0 AND v_opp_pieces_cnt > 0 THEN
        RETURN -9999; -- AI has lost
    END IF;

    RETURN v_score;
END evaluate_board;