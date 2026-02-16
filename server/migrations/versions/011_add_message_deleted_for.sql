-- Миграция 011: Удаление сообщения «только для себя»
-- Таблица для хранения сообщений, скрытых от конкретного пользователя
CREATE TABLE IF NOT EXISTS message_deleted_for (
  user_id INTEGER NOT NULL,
  message_id INTEGER NOT NULL,
  deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, message_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_message_deleted_for_user ON message_deleted_for(user_id);
