CREATE TABLE game_rules (
    rule_id             INT NOT NULL,
    rule_name           VARCHAR2(50) NOT NULL,
    board_size          INT DEFAULT 8 NOT NULL,
    rule_description    VARCHAR2(1000),
    CONSTRAINT pk_game_rules PRIMARY KEY (rule_id),
    CONSTRAINT uk_game_rules_name UNIQUE (rule_name)
);

INSERT INTO game_rules (rule_id, rule_name, board_size, rule_description)
VALUES (1, 'Русские шашки 8x8', 8, 'Русские шашки: доска 8x8, 12 шашек у каждого игрока. Простые шашки ходят только вперед по диагонали. Взятие обязательно, при возможности множественного взятия выбирается максимальное. Дамка ходит на любое расстояние по диагонали. Превращение в дамку происходит при достижении последнего ряда (сразу во время хода для русских шашек).');
INSERT INTO game_rules (rule_id, rule_name, board_size, rule_description)
VALUES (2, 'Международные шашки 10x10', 10, 'Международные шашки: доска 10x10, 20 шашек у каждого игрока. Простые шашки ходят только вперед по диагонали. Взятие обязательно, при возможности множественного взятия выбирается максимальное. Дамка ходит на любое расстояние по диагонали. Превращение в дамку происходит только при остановке на последнем ряду (не во время хода).');