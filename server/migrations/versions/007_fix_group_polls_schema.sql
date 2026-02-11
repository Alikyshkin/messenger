-- Миграция 007: Исправление схемы таблиц group_polls и group_poll_votes
-- Исправляет несоответствие между миграцией и кодом

-- Исправляем таблицу group_polls
-- Создаем временную таблицу с правильной структурой
CREATE TABLE group_polls_temp (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_message_id INTEGER NOT NULL UNIQUE,
  question TEXT NOT NULL,
  options TEXT NOT NULL,
  multiple INTEGER DEFAULT 0,
  FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE
);

-- Копируем данные из старой таблицы
-- Используем прямое копирование с правильными именами колонок
INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
SELECT 
  id,
  COALESCE(
    (SELECT group_message_id FROM group_polls WHERE group_polls.id = gp.id),
    (SELECT message_id FROM group_polls WHERE group_polls.id = gp.id)
  ) as group_message_id,
  question,
  options,
  COALESCE(
    (SELECT multiple FROM group_polls WHERE group_polls.id = gp.id),
    0
  ) as multiple
FROM group_polls AS gp;

-- Удаляем старую таблицу
DROP TABLE group_polls;

-- Переименовываем новую таблицу
ALTER TABLE group_polls_temp RENAME TO group_polls;

-- Исправляем таблицу group_poll_votes
-- Создаем новую таблицу с правильной структурой
CREATE TABLE group_poll_votes_temp (
  group_poll_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  option_index INTEGER NOT NULL,
  PRIMARY KEY (group_poll_id, user_id, option_index),
  FOREIGN KEY (group_poll_id) REFERENCES group_polls(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Копируем данные из старой таблицы
-- Используем прямое копирование с правильными именами колонок
INSERT INTO group_poll_votes_temp (group_poll_id, user_id, option_index)
SELECT 
  COALESCE(
    (SELECT group_poll_id FROM group_poll_votes WHERE group_poll_votes.user_id = gpv.user_id AND group_poll_votes.option_index = gpv.option_index LIMIT 1),
    (SELECT poll_id FROM group_poll_votes WHERE group_poll_votes.user_id = gpv.user_id AND group_poll_votes.option_index = gpv.option_index LIMIT 1)
  ) as group_poll_id,
  user_id,
  option_index
FROM group_poll_votes AS gpv;

-- Удаляем старую таблицу
DROP TABLE group_poll_votes;

-- Переименовываем новую таблицу
ALTER TABLE group_poll_votes_temp RENAME TO group_poll_votes;

-- Создаем индексы
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
