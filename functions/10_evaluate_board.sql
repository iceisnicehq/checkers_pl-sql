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
    v_score         NUMBER := 0;
    v_piece         CHAR(1);
    
    -- [ИЗМЕНЕНИЕ] Динамические переменные
    v_total_squares PLS_INTEGER;
    v_board_size    PLS_INTEGER;
    
    -- Weights for pieces and positions (остаются без изменений)
    c_man_value     CONSTANT NUMBER := 10;
    c_king_value    CONSTANT NUMBER := 50;
    c_side_val      CONSTANT NUMBER := 20; 
    c_wall_val      CONSTANT NUMBER := 10; 

BEGIN
    -- [ИЗМЕНЕНИЕ] Определяем размер доски "на лету"
    v_total_squares := LENGTH(p_board);
    v_board_size    := SQRT(v_total_squares);
    
    -- [ИЗМЕНЕНИЕ] Убеждаемся, что кэш карт (g_map_*) готов
    p_init_board_map(v_board_size);

    -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
    FOR i IN 1..v_total_squares LOOP
        v_piece := SUBSTR(p_board, i, 1);
        IF v_piece != c_empty_field THEN
            DECLARE
                v_piece_value    NUMBER;
                v_multiplier     NUMBER;
                v_piece_color    CHAR(1);
                
                -- [ИЗМЕНЕНИЕ] Получаем v_row и v_col из кэша
                v_field_rec      rec_board_field := g_map_by_idx(i);
                v_row            PLS_INTEGER     := v_field_rec.row_num;
                v_col            PLS_INTEGER     := v_field_rec.col_num;
                
                v_position_bonus NUMBER := 0;
            BEGIN
                -- 1. Determine piece ownership and value
                v_piece_color := CASE WHEN v_piece IN ('w', 'W') THEN 'W' ELSE 'B' END;
                v_multiplier  := CASE WHEN v_piece_color = p_ai_color THEN 1 ELSE -1 END;
                v_piece_value := CASE WHEN v_piece IN ('W', 'B') THEN c_king_value ELSE c_man_value END;
                
                -- Add the basic material score
                v_score := v_score + (v_piece_value * v_multiplier);

                -- 2. Calculate and add positional bonuses
                IF p_difficulty < 2 THEN
                    -- [ИЗМЕНЕНИЕ] Бонус за борт (1 или 8 -> 1 или v_board_size)
                    IF v_col = 1 OR v_col = v_board_size THEN
                        v_position_bonus := v_position_bonus + c_side_val;
                    END IF;

                    -- [ИЗМЕНЕНИЕ] Бонус за продвижение
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
    
    -- Check for terminal win/loss state
    DECLARE
        v_ai_pieces    PLS_INTEGER := 0;
        v_opp_pieces   PLS_INTEGER := 0;
    BEGIN
        -- [ИЗМЕНЕНИЕ] Цикл по v_total_squares
        FOR k IN 1..v_total_squares LOOP
            IF SUBSTR(p_board, k, 1) != c_empty_field THEN
                IF (CASE WHEN SUBSTR(p_board, k, 1) IN ('w', 'W') THEN 'W' ELSE 'B' END) = p_ai_color THEN
                    v_ai_pieces := 1;
                ELSE
                    v_opp_pieces := 1;
                END IF;
            END IF;
            IF v_ai_pieces > 0 AND v_opp_pieces > 0 THEN
                EXIT;
            END IF;
        END LOOP;

        IF v_ai_pieces > 0 AND v_opp_pieces = 0 THEN
            RETURN 9999; -- AI has won
        ELSIF v_ai_pieces = 0 AND v_opp_pieces > 0 THEN
            RETURN -9999; -- AI has lost
        END IF;
    END;

    RETURN v_score;
END evaluate_board;