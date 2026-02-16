-- Миграция 013: Настройки приватности пользователя
CREATE TABLE IF NOT EXISTS user_privacy (
  user_id INTEGER PRIMARY KEY,
  who_can_see_status TEXT DEFAULT 'contacts',
  who_can_message TEXT DEFAULT 'contacts',
  who_can_call TEXT DEFAULT 'contacts',
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CHECK (who_can_see_status IN ('all', 'contacts', 'nobody')),
  CHECK (who_can_message IN ('all', 'contacts', 'nobody')),
  CHECK (who_can_call IN ('all', 'contacts', 'nobody'))
);
