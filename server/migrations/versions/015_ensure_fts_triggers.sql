-- Миграция 015: Гарантировать корректные FTS триггеры (исправление 500 на PATCH /messages/:peerId/read)
-- Старые триггеры из миграции 003 могли ссылаться на несуществующую колонку message_id в FTS.
-- Удаляем и пересоздаём триггеры с правильной схемой (только rowid, content).

DROP TRIGGER IF EXISTS messages_fts_insert;
DROP TRIGGER IF EXISTS messages_fts_update;
DROP TRIGGER IF EXISTS messages_fts_delete;

CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, content) VALUES (new.id, COALESCE(new.content, ''));
END;
CREATE TRIGGER messages_fts_update AFTER UPDATE ON messages BEGIN
  UPDATE messages_fts SET content = COALESCE(new.content, '') WHERE rowid = new.id;
END;
CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
  DELETE FROM messages_fts WHERE rowid = old.id;
END;
