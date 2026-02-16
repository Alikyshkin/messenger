-- Миграция 014: Скрыть статус от конкретных пользователей
CREATE TABLE IF NOT EXISTS user_privacy_hide_from (
  user_id INTEGER NOT NULL,
  hidden_from_user_id INTEGER NOT NULL,
  PRIMARY KEY (user_id, hidden_from_user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (hidden_from_user_id) REFERENCES users(id) ON DELETE CASCADE,
  CHECK (user_id != hidden_from_user_id)
);
CREATE INDEX IF NOT EXISTS idx_privacy_hide_from_user ON user_privacy_hide_from(user_id);
