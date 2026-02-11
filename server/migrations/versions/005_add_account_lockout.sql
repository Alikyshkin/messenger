-- Миграция 005: Добавление полей для блокировки аккаунта

ALTER TABLE users ADD COLUMN failed_login_attempts INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN last_failed_login DATETIME;
ALTER TABLE users ADD COLUMN locked_until DATETIME;

CREATE INDEX IF NOT EXISTS idx_users_locked_until ON users(locked_until) WHERE locked_until IS NOT NULL;
