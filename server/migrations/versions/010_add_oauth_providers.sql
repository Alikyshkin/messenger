-- Миграция 010: OAuth провайдеры и вход по телефону
-- Добавляем колонки для привязки аккаунтов к внешним провайдерам

-- OAuth идентификаторы (Google, VK, Telegram)
ALTER TABLE users ADD COLUMN google_id TEXT;
ALTER TABLE users ADD COLUMN vk_id TEXT;
ALTER TABLE users ADD COLUMN telegram_id TEXT;

-- Индексы для быстрого поиска по OAuth ID
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_vk_id ON users(vk_id) WHERE vk_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id) WHERE telegram_id IS NOT NULL;

-- Таблица кодов верификации телефона (для входа по номеру)
CREATE TABLE IF NOT EXISTS phone_verification_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_phone_codes_phone ON phone_verification_codes(phone);
CREATE INDEX IF NOT EXISTS idx_phone_codes_expires ON phone_verification_codes(expires_at);
