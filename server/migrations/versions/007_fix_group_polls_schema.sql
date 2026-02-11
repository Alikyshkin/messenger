-- Миграция 007: Исправление схемы таблиц group_polls и group_poll_votes
-- Исправляет несоответствие между миграцией и кодом

-- Исправляем таблицу group_polls
-- Создаем временную таблицу с правильной структурой
CREATE TABLE IF NOT EXISTS group_polls_temp (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_message_id INTEGER NOT NULL UNIQUE,
  question TEXT NOT NULL,
  options TEXT NOT NULL,
  multiple INTEGER DEFAULT 0,
  FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE
);

-- Копируем данные из старой таблицы group_polls, если она существует
-- Используем message_id (старое название), так как group_message_id может еще не существовать
-- Если таблицы нет или она пустая, INSERT просто не выполнится (но это нормально - создадим пустую таблицу)
INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
SELECT 
  id,
  CASE 
    WHEN EXISTS (SELECT name FROM pragma_table_info('group_polls') WHERE name = 'group_message_id')
    THEN group_message_id
    ELSE message_id
  END,
  question,
  options,
  COALESCE(multiple, 0)
FROM group_polls
WHERE EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='group_polls');

-- Удаляем старую таблицу
DROP TABLE IF EXISTS group_polls;

-- Переименовываем новую таблицу
ALTER TABLE group_polls_temp RENAME TO group_polls;

-- Исправляем таблицу group_poll_votes
-- Создаем новую таблицу с правильной структурой
CREATE TABLE IF NOT EXISTS group_poll_votes_temp (
  group_poll_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  option_index INTEGER NOT NULL,
  PRIMARY KEY (group_poll_id, user_id, option_index),
  FOREIGN KEY (group_poll_id) REFERENCES group_polls(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Копируем данные из старой таблицы group_poll_votes, если она существует и имеет колонку poll_id
-- Используем poll_id (старое название), так как group_poll_id еще не существует
-- Если таблицы нет или она пустая, INSERT просто не выполнится (но это нормально - создадим пустую таблицу)
INSERT INTO group_poll_votes_temp (group_poll_id, user_id, option_index)
SELECT 
  poll_id as group_poll_id,
  user_id,
  option_index
FROM group_poll_votes
WHERE EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='group_poll_votes')
  AND EXISTS (SELECT 1 FROM pragma_table_info('group_poll_votes') WHERE name = 'poll_id');

-- Удаляем старую таблицу
DROP TABLE IF EXISTS group_poll_votes;

-- Переименовываем новую таблицу
ALTER TABLE group_poll_votes_temp RENAME TO group_poll_votes;

-- Создаем индексы
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
