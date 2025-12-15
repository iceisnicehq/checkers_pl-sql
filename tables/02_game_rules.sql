CREATE TABLE game_rules (
    rule_id             INT NOT NULL,
    rule_name           VARCHAR2(50) NOT NULL,
    board_size          INT DEFAULT 8 NOT NULL,
    rule_description    VARCHAR2(1000),
    CONSTRAINT pk_game_rules PRIMARY KEY (rule_id),
    CONSTRAINT uk_game_rules_name UNIQUE (rule_name)
);