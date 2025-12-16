# Подсказки для тестирования игры "Шашки на Oracle"

Этот документ содержит подсказки для быстрого тестирования различных сценариев игры без необходимости доигрывать полные партии.

---

## Быстрое завершение игр

### 1. Сдача в игре

Самый быстрый способ завершить игру:

```sql
-- Создать игру
BEGIN game_logic.create_game(p_ai_difficulty => 'E'); END;

-- Сразу сдаться
BEGIN game_logic.resign_game; END;
```

### 2. Установка позиции доски через вставку хода

**ВАЖНО:** Состояние доски хранится в таблице `game_moves` (последний ход) или берется из начальной позиции/задачи. В таблице `games` нет поля `board_position`.

Для тестирования завершения игры можно вставить ход в `game_moves` с нужной позицией доски.

**Пример: Позиция с одной белой шашкой (белые выигрывают)**

```sql
-- Найти активную игру
SELECT game_id, rule_id FROM games WHERE status = 'A' AND ROWNUM = 1;

-- Удалить все существующие ходы (если есть)
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с нужной позицией доски
-- Позиция: одна белая шашка на a1, черных нет (для 8x8)
-- Декодированная позиция: 63 пустых, 1 белая = '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++w'
-- Закодированная позиция (RLE): '62w1'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '62w1');
COMMIT;

-- Установить очередь хода белых
UPDATE games SET current_turn = 'W' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Сделать один ход для завершения (любой ход белых завершит игру победой)
BEGIN game_logic.make_move('a1-b2'); END;
```

**Пример: Позиция с одной черной шашкой (черные выигрывают)**

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: одна черная шашка на h8, белых нет
-- Декодированная позиция: 63 пустых, 1 черная = '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++b'
-- Закодированная позиция (RLE): '63b'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '1b62');
COMMIT;

-- Установить очередь хода черных
UPDATE games SET current_turn = 'B' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Сделать один ход для завершения
BEGIN game_logic.make_move('h8-g7'); END;
```

**Пример: Позиция для ничьей (оба игрока заблокированы)**

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: белые на a1, черные на h8, оба заблокированы
-- Декодированная позиция: 1 белая, 62 пустых, 1 черная = 'w++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++b'
-- Закодированная позиция (RLE): 'w62b'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', 'w62b');
COMMIT;

-- Предложить ничью
BEGIN game_logic.draw('O'); END;
-- Принять ничью (от другого игрока)
BEGIN game_logic.draw('A'); END;
```

---

## Примеры ходов для тестирования

### Русские шашки (8x8)

**Тихие ходы (начальная позиция):**
- `c3-d4` - белые
- `b6-a5` - черные
- `e3-f4` - белые
- `f6-e5` - черные

**Взятия:**
- `c3:e5` - белые бьют черную на d4
- `d6:f4` - черные бьют белую на e5
- `h4:f6:d8` - многоходовое взятие белых

**Превращение в дамку:**
- `f2-g1` - белая простая превращается в дамку (русские шашки - сразу)
- После превращения дамка может ходить: `g1-h2`, `g1-f2`, `g1-e3` и т.д.

### Международные шашки (10x10)

**Тихие ходы (начальная позиция):**
- `c4-d5` - белые
- `b7-a6` - черные
- `e4-f5` - белые
- `f7-e6` - черные

**Взятия:**
- `c4:e6` - белые бьют черную на d5
- `d7:f5` - черные бьют белую на e6
- `h5:f7:d9:b7` - многоходовое взятие белых

---

## Позиции для быстрого тестирования завершения

### Позиция 1: Белые выигрывают (нет черных фигур)

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: только белые шашки (для 8x8)
-- Декодированная позиция: 32 белых, 32 пустых
-- Закодированная позиция (RLE): '32w32'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '32w32');
COMMIT;

-- Установить очередь хода белых
UPDATE games SET current_turn = 'W' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Любой ход белых завершит игру победой
BEGIN game_logic.make_move('a1-b2'); END;
```

### Позиция 2: Черные выигрывают (нет белых фигур)

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: только черные шашки (для 8x8)
-- Закодированная позиция (RLE): '32b32'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '32b32');
COMMIT;

-- Установить очередь хода черных
UPDATE games SET current_turn = 'B' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Любой ход черных завершит игру победой
BEGIN game_logic.make_move('h8-g7'); END;
```

### Позиция 3: Ничья по лимиту ходов без взятий

**Примечание:** Лимит ходов без взятий проверяется динамически при каждом ходе. Для тестирования нужно сделать несколько тихих ходов подряд.

```sql
-- Установить лимит ходов без взятий
UPDATE games 
SET draw_moves_limit = 5
WHERE game_id = <ваш_game_id>;
COMMIT;

-- Сделать несколько тихих ходов подряд (без взятий)
-- После 5 полуходов без взятий игра завершится ничьей
BEGIN game_logic.make_move('c3-d4'); END;  -- Тихий ход 1
BEGIN game_logic.make_move('b6-a5'); END;  -- Тихий ход 2
BEGIN game_logic.make_move('e3-f4'); END;  -- Тихий ход 3
BEGIN game_logic.make_move('f6-e5'); END;  -- Тихий ход 4
BEGIN game_logic.make_move('d2-c3'); END;  -- Тихий ход 5 - ничья
```

### Позиция 4: Таймаут на ход

**Примечание:** Таймаут на ход проверяется через DBMS_SCHEDULER jobs. Для тестирования можно установить время последнего хода в прошлом.

```sql
-- Установить таймаут на ход
UPDATE games 
SET time_limit_move_sec = 60
WHERE game_id = <ваш_game_id>;
COMMIT;

-- Установить время последнего хода в прошлом (если есть ходы)
UPDATE game_moves 
SET move_timestamp = SYSDATE - INTERVAL '61' SECOND
WHERE game_id = <ваш_game_id> 
  AND move_number = (SELECT MAX(move_number) FROM game_moves WHERE game_id = <ваш_game_id>);
COMMIT;

-- Попытка сделать ход может вызвать таймаут (зависит от реализации проверки)
BEGIN game_logic.make_move('a1-b2'); END;
```

### Позиция 5: Таймаут на партию

```sql
-- Установить таймаут на партию и время игрока
UPDATE games 
SET time_limit_game_sec = 3600,
    time_white_remaining_sec = 0,  -- Время белых истекло
    current_turn = 'W'
WHERE game_id = <ваш_game_id>;
COMMIT;

-- Попытка сделать ход вызовет таймаут
BEGIN game_logic.make_move('a1-b2'); END;
```

---

## Тестирование превращения в дамку

### Русские шашки (превращение сразу во время хода)

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: белая шашка на f2, может пойти на g1 и превратиться
-- Для 8x8: позиция с белой шашкой на f2 (примерная позиция)
-- Закодированная позиция (RLE): примерно '30f1w33'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '30f1w33');
COMMIT;

-- Установить очередь хода белых
UPDATE games SET current_turn = 'W' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Ход с превращением
BEGIN game_logic.make_move('f2-g1'); END;
-- Шашка превратится в дамку сразу, даже если есть продолжение взятия
```

### Международные шашки (превращение при остановке)

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: белая шашка на f2, может пойти на g1 и превратиться
-- Для 10x10: позиция с белой шашкой на f2 (примерная позиция)
-- Закодированная позиция (RLE): примерно '50f1w49'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '50f1w49');
COMMIT;

-- Установить очередь хода белых и правило
UPDATE games 
SET current_turn = 'W', rule_id = 2 
WHERE game_id = <ваш_game_id>;
COMMIT;

-- Ход с превращением
BEGIN game_logic.make_move('f2-g1'); END;
-- Шашка превратится в дамку только при остановке на последней горизонтали
```

---

## Тестирование обязательного взятия

```sql
-- Удалить все существующие ходы
DELETE FROM game_moves WHERE game_id = <ваш_game_id>;
COMMIT;

-- Вставить ход с позицией: есть обязательное взятие
-- Например, белая на c3, черная на d4, белые обязаны бить
-- Для 8x8: примерная позиция с обязательным взятием
-- Закодированная позиция (RLE): примерно '20c2w1b41'
INSERT INTO game_moves (game_id, move_number, move_notation, is_capture, board_position)
VALUES (<ваш_game_id>, 0, 'setup', 'N', '20c2w1b41');
COMMIT;

-- Установить очередь хода белых
UPDATE games SET current_turn = 'W' WHERE game_id = <ваш_game_id>;
COMMIT;

-- Попытка тихого хода должна быть отклонена
BEGIN game_logic.make_move('c3-d4'); END;  -- Ошибка: обязательное взятие

-- Правильный ход - взятие
BEGIN game_logic.make_move('c3:e5'); END;  -- Успешно
```

---

## Тестирование матчей

### Быстрое завершение матча

```sql
-- Создать матч best of 3
BEGIN game_logic.create_match(p_games_to_win => 3); END;

-- Присоединиться к матчу (от другого пользователя)
BEGIN game_logic.join_match(p_match_id => <match_id>); END;

-- Для каждой игры в матче:
-- 1. Создать позицию близкую к завершению
-- 2. Сделать один ход для победы
-- 3. Матч автоматически создаст следующую игру
-- 4. После 2 побед одного игрока матч завершится
```

---

## Тестирование задач (Puzzles)

### Использование существующих задач

```sql
-- Просмотреть доступные задачи
BEGIN game_logic.show_puzzles; END;

-- Создать игру с задачей
BEGIN game_logic.create_game(p_puzzle_id => 1); END;

-- Просмотреть решение (если были попытки)
BEGIN game_logic.show_puzzles(p_puzzle_id => 1, p_solution => 'Y'); END;
```

### Создание тестовой задачи

```sql
-- Создать простую задачу для тестирования
BEGIN
    game_logic.create_puzzle(
        p_board_position => '1w63+',  -- Одна белая шашка
        p_turn_to_move => 'W',
        p_moves_to_solve => 1,
        p_difficulty_level => 'E'
    );
END;
```

**Примечание:** Для создания задач можно использовать готовые позиции досок из файла `tables/15_insert_puzzles.sql`. В этом файле содержатся примеры задач с различными позициями в формате RLE, которые можно использовать как шаблоны для создания собственных задач через процедуру `create_puzzle`.

---

## Тестирование ежедневной задачи

```sql
-- Просмотреть ежедневную задачу
BEGIN game_logic.show_daily_puzzle; END;

-- Создать игру с ежедневной задачей
BEGIN game_logic.create_game(p_daily => 'Y'); END;

-- Решить задачу (получить +5 рейтинга, только один раз в день)
-- После решения игра завершится автоматически
```

---

## Тестирование рейтингов

### Быстрое изменение рейтинга для тестирования

```sql
-- Найти рейтинг игрока
SELECT * FROM player_ratings WHERE player_id = <player_id>;

-- Установить рейтинг в 0 для тестирования минимального значения
UPDATE player_ratings 
SET rating = 0
WHERE player_id = <player_id> AND rule_id = 1;
COMMIT;

-- Создать игру и выиграть
-- Рейтинг должен остаться 0 (не может быть отрицательным)
```

### Тестирование сезонных рейтингов

```sql
-- Создать новый сезон вручную
INSERT INTO seasons (season_name, start_date, end_date, is_active)
VALUES ('Тестовый сезон', SYSDATE, SYSDATE + 30, 'Y');
COMMIT;

-- Триггер автоматически создаст рейтинги для всех игроков
-- Начальный рейтинг = GREATEST(500, старый_рейтинг * 0.8)
```

---

## Тестирование представлений (Views)

```sql
-- Просмотр открытых игр
SELECT * FROM v_open_games;

-- Просмотр активных игр
SELECT * FROM v_active_games;

-- Просмотр завершенных игр
SELECT * FROM v_ended_games;

-- Просмотр протокола игры
SELECT * FROM v_game_protocol WHERE game_id = <game_id> ORDER BY move_number;

-- Просмотр истории игрока
SELECT * FROM v_player_history WHERE player_name = USER;

-- Просмотр рейтингов
SELECT * FROM v_player_ratings ORDER BY rating DESC;

-- Просмотр результатов ежедневных задач
SELECT * FROM v_daily_puzzle_results;
```

---

## Полезные SQL запросы для тестирования

### Очистка тестовых данных

```sql
-- Удалить все игры (осторожно!)
DELETE FROM games;
COMMIT;

-- Удалить всех игроков (осторожно!)
DELETE FROM players;
COMMIT;

-- Удалить все рейтинги (осторожно!)
DELETE FROM player_ratings;
COMMIT;
```

### Просмотр текущего состояния

```sql
-- Активные игры
SELECT game_id, status, current_turn, player_white_id, player_black_id 
FROM games 
WHERE status IN ('A', 'O', 'C');

-- Последние ходы
SELECT * FROM game_moves 
ORDER BY move_timestamp DESC 
FETCH FIRST 10 ROWS ONLY;

-- Рейтинги игроков
SELECT p.username, pr.rating, r.rule_name, s.season_name
FROM player_ratings pr
JOIN players p ON pr.player_id = p.player_id
JOIN game_rules r ON pr.rule_id = r.rule_id
JOIN seasons s ON pr.season_id = s.season_id
ORDER BY pr.rating DESC;
```

---

## Примечания

1. **RLE формат позиций**: Позиции хранятся в сжатом формате (Run-Length Encoding) в таблице `game_moves.board_position`. Например, `12b4b5b2b8w1b1w11w3w8` означает: 12 пустых, 4 черных, 5 пустых, 2 черных, 8 пустых, 1 белая, 1 черная, 1 белая, 11 пустых, 3 белых, 8 пустых. Текущее состояние доски берется из последнего хода в `game_moves` или из начальной позиции/задачи, если ходов нет.

2. **Установка позиции для тестирования**: Для установки нужной позиции доски нужно вставить запись в `game_moves` с закодированной позицией (используя функцию `encode_board`). Можно использовать `move_number = 0` для "установочного" хода. После этого удалить все существующие ходы или использовать новую игру.

3. **Координаты**: Используется алгебраическая нотация:
   - Для 8x8: a1-h8
   - Для 10x10: a1-j10
   - Строки: 1-8 (или 1-10)
   - Столбцы: A-H (или A-J)

4. **Обязательное взятие**: Если есть возможность взятия, тихий ход будет отклонен.

5. **Максимальное взятие**: В международных шашках обязательно выбирать взятие с максимальным количеством фигур.

6. **Превращение**: 
   - Русские шашки: превращение происходит сразу при достижении последней горизонтали, даже во время многоходового взятия.
   - Международные шашки: превращение происходит только при остановке на последней горизонтали.

---

## Тестирование автоматических заданий (Schedulers)

### Проверка статуса всех jobs

```sql
-- Просмотр всех jobs
SELECT job_name, enabled, state, last_start_date, next_run_date, run_count, failure_count
FROM user_scheduler_jobs
WHERE job_name LIKE '%CHECKERS%' OR job_name LIKE '%SEASONS%' OR job_name LIKE '%TIMEOUT%'
ORDER BY job_name;

-- Просмотр истории выполнения jobs
SELECT job_name, log_date, status, error#, additional_info
FROM user_scheduler_job_log
WHERE job_name IN ('DAILY_CHECKERS_PUZZLE_JOB', 'MONTHLY_SEASONS_JOB', 'INACTIVE_SESSIONS_TIMEOUT_JOB')
ORDER BY log_date DESC
FETCH FIRST 20 ROWS ONLY;
```

### Запуск job принудительно

```sql
-- Запустить job немедленно
BEGIN
    DBMS_SCHEDULER.RUN_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB', use_current_session => FALSE);
END;
/

-- Проверить результат выполнения
SELECT * FROM daily_puzzles WHERE puzzle_date = TRUNC(SYSDATE);
```

### Тестирование DAILY_CHECKERS_PUZZLE_JOB (ежедневная задача)

```sql
-- 1. Проверить текущее состояние
SELECT * FROM daily_puzzles WHERE puzzle_date = TRUNC(SYSDATE);

-- 2. Удалить задачу на сегодня (если есть) для тестирования
DELETE FROM daily_puzzles WHERE puzzle_date = TRUNC(SYSDATE);
COMMIT;

-- 3. Запустить job принудительно
BEGIN
    DBMS_SCHEDULER.RUN_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB', use_current_session => FALSE);
END;
/

-- 4. Проверить результат
SELECT dp.puzzle_date, dp.puzzle_id, p.difficulty_level, p.moves_to_solve
FROM daily_puzzles dp
JOIN puzzles p ON dp.puzzle_id = p.puzzle_id
WHERE dp.puzzle_date = TRUNC(SYSDATE);

-- 5. Проверить, что задача создается только один раз
-- Повторный запуск не должен создавать новую запись
BEGIN
    DBMS_SCHEDULER.RUN_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB', use_current_session => FALSE);
END;
/
-- Проверить, что запись все еще одна
SELECT COUNT(*) FROM daily_puzzles WHERE puzzle_date = TRUNC(SYSDATE);  -- Должно быть 1
```

### Тестирование MONTHLY_SEASONS_JOB (создание сезонов)

```sql
-- 1. Проверить текущие сезоны
SELECT * FROM seasons ORDER BY season_id DESC;

-- 2. Проверить активный сезон для текущего месяца
SELECT * FROM seasons 
WHERE start_date <= TRUNC(SYSDATE, 'MM') 
  AND end_date >= TRUNC(SYSDATE, 'MM');

-- 3. Удалить сезон для текущего месяца (если есть) для тестирования
DELETE FROM seasons 
WHERE start_date <= TRUNC(SYSDATE, 'MM') 
  AND end_date >= TRUNC(SYSDATE, 'MM');
COMMIT;

-- 4. Запустить job принудительно
BEGIN
    DBMS_SCHEDULER.RUN_JOB(job_name => 'MONTHLY_SEASONS_JOB', use_current_session => FALSE);
END;
/

-- 5. Проверить, что сезон создан
SELECT * FROM seasons 
WHERE start_date <= TRUNC(SYSDATE, 'MM') 
  AND end_date >= TRUNC(SYSDATE, 'MM');

-- 6. Проверить, что триггер trg_init_season_ratings сработал
-- Должны быть созданы рейтинги для всех игроков в новом сезоне
SELECT COUNT(*) as ratings_count, season_id
FROM player_ratings
WHERE season_id = (SELECT MAX(season_id) FROM seasons)
GROUP BY season_id;

-- 7. Проверить начальные рейтинги в новом сезоне
-- Для игроков с рейтингом в предыдущем сезоне: GREATEST(500, старый_рейтинг * 0.8)
-- Для новых игроков: 500
SELECT 
    p.username,
    pr_old.rating as old_rating,
    pr_new.rating as new_rating,
    GREATEST(500, ROUND(pr_old.rating * 0.8)) as expected_rating
FROM player_ratings pr_new
JOIN players p ON pr_new.player_id = p.player_id
LEFT JOIN player_ratings pr_old ON (
    pr_old.player_id = pr_new.player_id 
    AND pr_old.rule_id = pr_new.rule_id
    AND pr_old.season_id = (
        SELECT MAX(season_id) 
        FROM seasons 
        WHERE season_id < pr_new.season_id
    )
)
WHERE pr_new.season_id = (SELECT MAX(season_id) FROM seasons)
  AND pr_new.rule_id = 1
ORDER BY p.username;
```

### Тестирование триггера trg_init_season_ratings

```sql
-- 1. Проверить текущее количество игроков и их рейтинги
SELECT COUNT(DISTINCT player_id) as players_count FROM players;
SELECT COUNT(*) as ratings_count FROM player_ratings;

-- 2. Создать новый сезон вручную (триггер должен сработать автоматически)
INSERT INTO seasons (season_name, start_date, end_date, is_active)
VALUES ('Тестовый сезон', SYSDATE, SYSDATE + 30, 'Y');
COMMIT;

-- 3. Проверить, что триггер создал рейтинги для всех игроков
-- Количество рейтингов = количество игроков * количество правил (обычно 2)
SELECT 
    COUNT(*) as total_ratings,
    COUNT(DISTINCT player_id) as players_with_ratings,
    COUNT(DISTINCT rule_id) as rules_count
FROM player_ratings
WHERE season_id = (SELECT MAX(season_id) FROM seasons);

-- 4. Проверить начальные рейтинги
-- Для игроков с рейтингом в предыдущем сезоне: GREATEST(500, старый_рейтинг * 0.8)
-- Для новых игроков: 500
SELECT 
    p.username,
    pr.rule_id,
    pr.rating,
    CASE 
        WHEN pr.rating = 500 THEN 'Новый игрок или низкий рейтинг'
        ELSE 'Рассчитан из предыдущего сезона'
    END as rating_type
FROM player_ratings pr
JOIN players p ON pr.player_id = p.player_id
WHERE pr.season_id = (SELECT MAX(season_id) FROM seasons)
ORDER BY p.username, pr.rule_id;

-- 5. Проверить, что нет дубликатов рейтингов
SELECT player_id, rule_id, season_id, COUNT(*) as count
FROM player_ratings
WHERE season_id = (SELECT MAX(season_id) FROM seasons)
GROUP BY player_id, rule_id, season_id
HAVING COUNT(*) > 1;  -- Не должно быть строк
```

### Тестирование INACTIVE_SESSIONS_TIMEOUT_JOB (закрытие неактивных сессий)

```sql
-- 1. Создать игру для тестирования
BEGIN game_logic.create_game(p_ai_difficulty => 'E'); END;
/

-- 2. Найти game_id
SELECT game_id, start_time, status FROM games WHERE status = 'A' AND ROWNUM = 1;

-- 3. Установить время последнего хода в прошлом (более 24 часов назад)
-- Если есть ходы, обновить их время
UPDATE game_moves 
SET move_timestamp = SYSDATE - INTERVAL '25' HOUR
WHERE game_id = <ваш_game_id>;
COMMIT;

-- Если ходов нет, обновить start_time игры
UPDATE games 
SET start_time = SYSDATE - INTERVAL '25' HOUR
WHERE game_id = <ваш_game_id>;
COMMIT;

-- 4. Запустить job принудительно
BEGIN
    DBMS_SCHEDULER.RUN_JOB(job_name => 'INACTIVE_SESSIONS_TIMEOUT_JOB', use_current_session => FALSE);
END;
/

-- 5. Проверить, что игра закрыта по таймауту
SELECT game_id, status, end_time, winner_player_color
FROM games 
WHERE game_id = <ваш_game_id>;
-- Статус должен быть 'T' (Timeout), end_time установлен, winner_player_color определен

-- 6. Проверить, что зрители отключены
SELECT * FROM spectators 
WHERE game_id = <ваш_game_id> AND left_at IS NOT NULL;
```

### Полезные команды для управления jobs

```sql
-- Включить job
BEGIN
    DBMS_SCHEDULER.ENABLE(name => 'DAILY_CHECKERS_PUZZLE_JOB');
END;
/

-- Выключить job
BEGIN
    DBMS_SCHEDULER.DISABLE(name => 'DAILY_CHECKERS_PUZZLE_JOB');
END;
/

-- Остановить выполняющийся job
BEGIN
    DBMS_SCHEDULER.STOP_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB', force => TRUE);
END;
/

-- Удалить job (для пересоздания)
BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'DAILY_CHECKERS_PUZZLE_JOB', force => TRUE);
END;
/
```

