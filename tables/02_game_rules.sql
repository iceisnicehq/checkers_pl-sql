-- 2. GAME_RULES
CREATE TABLE game_rules (
    rule_id             INT NOT NULL,
    rule_name           VARCHAR2(50) NOT NULL,
    board_size          INT DEFAULT 8 NOT NULL,
    rule_description    VARCHAR2(1000),
    CONSTRAINT pk_game_rules PRIMARY KEY (rule_id),
    CONSTRAINT uk_game_rules_name UNIQUE (rule_name)
);

INSERT INTO game_rules (rule_id, rule_name, board_size,rule_description)
VALUES (1, 'Русские шашки 8x8', 8, 'Blah blah blah Russan checkers rules description.');
INSERT INTO game_rules (rule_id, rule_name, board_size, rule_description)
VALUES (2, 'Международные шашки 10x10', 10, 'Blah blah blah International checkers rules description.');