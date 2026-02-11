-- Миграция 009: Приведение FTS триггеров в соответствие со схемой messages_fts
-- В db.js messages_fts создаётся без колонки message_id, а миграция 003 добавляла
-- триггеры с message_id. При UPDATE messages срабатывал триггер и падал с
-- "no such column: T.message_id". Пересоздаём FTS и триггеры без message_id.

-- Удаляем старые триггеры (могут ссылаться на несуществующую колонку message_id)
DROP TRIGGER IF EXISTS messages_fts_insert;
DROP TRIGGER IF EXISTS messages_fts_update;
DROP TRIGGER IF EXISTS messages_fts_delete;
DROP TRIGGER IF EXISTS group_messages_fts_insert;
DROP TRIGGER IF EXISTS group_messages_fts_update;
DROP TRIGGER IF EXISTS group_messages_fts_delete;

-- Пересоздаём FTS таблицы только с content (совместимо с db.js)
DROP TABLE IF EXISTS messages_fts;
CREATE VIRTUAL TABLE messages_fts USING fts5(
  content,
  content='messages',
  content_rowid='id'
);

DROP TABLE IF EXISTS group_messages_fts;
CREATE VIRTUAL TABLE group_messages_fts USING fts5(
  content,
  content='group_messages',
  content_rowid='id'
);

-- Триггеры без message_id
CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER messages_fts_update AFTER UPDATE ON messages BEGIN
  UPDATE messages_fts SET content = new.content WHERE rowid = new.id;
END;

CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
  DELETE FROM messages_fts WHERE rowid = old.id;
END;

CREATE TRIGGER group_messages_fts_insert AFTER INSERT ON group_messages BEGIN
  INSERT INTO group_messages_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER group_messages_fts_update AFTER UPDATE ON group_messages BEGIN
  UPDATE group_messages_fts SET content = new.content WHERE rowid = new.id;
END;

CREATE TRIGGER group_messages_fts_delete AFTER DELETE ON group_messages BEGIN
  DELETE FROM group_messages_fts WHERE rowid = old.id;
END;

-- Восстанавливаем индекс из существующих сообщений
INSERT OR IGNORE INTO messages_fts(rowid, content) SELECT id, content FROM messages;
INSERT OR IGNORE INTO group_messages_fts(rowid, content) SELECT id, content FROM group_messages;
