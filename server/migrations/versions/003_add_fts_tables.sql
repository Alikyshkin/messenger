-- Миграция 003: Добавление полнотекстового поиска (FTS5)

-- Виртуальная таблица для полнотекстового поиска по сообщениям
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
  message_id UNINDEXED,
  content,
  content='messages',
  content_rowid='id'
);

-- Виртуальная таблица для полнотекстового поиска по сообщениям в группах
CREATE VIRTUAL TABLE IF NOT EXISTS group_messages_fts USING fts5(
  message_id UNINDEXED,
  content,
  content='group_messages',
  content_rowid='id'
);

-- Триггеры для автоматической синхронизации FTS таблиц при вставке
CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, message_id, content) VALUES (new.id, new.id, new.content);
END;

CREATE TRIGGER IF NOT EXISTS group_messages_fts_insert AFTER INSERT ON group_messages BEGIN
  INSERT INTO group_messages_fts(rowid, message_id, content) VALUES (new.id, new.id, new.content);
END;

-- Триггеры для автоматической синхронизации FTS таблиц при обновлении
CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE ON messages BEGIN
  UPDATE messages_fts SET content = new.content WHERE rowid = new.id;
END;

CREATE TRIGGER IF NOT EXISTS group_messages_fts_update AFTER UPDATE ON group_messages BEGIN
  UPDATE group_messages_fts SET content = new.content WHERE rowid = new.id;
END;

-- Триггеры для автоматической синхронизации FTS таблиц при удалении
CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN
  DELETE FROM messages_fts WHERE rowid = old.id;
END;

CREATE TRIGGER IF NOT EXISTS group_messages_fts_delete AFTER DELETE ON group_messages BEGIN
  DELETE FROM group_messages_fts WHERE rowid = old.id;
END;
