import Database from 'better-sqlite3';
import { mkdirSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { runMigrations } from './migrations/index.js';
import { log } from './utils/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, 'messenger.db');
const dbDir = dirname(dbPath);
if (!existsSync(dbDir)) mkdirSync(dbDir, { recursive: true });

// Применяем миграции перед созданием подключения
try {
  runMigrations(dbPath);
} catch (error) {
  log.error({ error }, 'Ошибка при применении миграций');
  // Продолжаем выполнение для обратной совместимости
}

const db = new Database(dbPath);

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  
  CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
  CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
  CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;

  CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    contact_id INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, contact_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (contact_id) REFERENCES users(id)
  );

  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    read_at DATETIME,
    FOREIGN KEY (sender_id) REFERENCES users(id),
    FOREIGN KEY (receiver_id) REFERENCES users(id)
  );
  
  -- Полнотекстовый поиск для сообщений
  CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='id'
  );

  CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
  CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
  CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
  CREATE INDEX IF NOT EXISTS idx_messages_sender_receiver ON messages(sender_id, receiver_id);
  CREATE INDEX IF NOT EXISTS idx_messages_receiver_read ON messages(receiver_id, read_at);
  CREATE INDEX IF NOT EXISTS idx_messages_created_desc ON messages(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id);
  CREATE INDEX IF NOT EXISTS idx_contacts_contact ON contacts(contact_id);
`);

// Заявки в друзья: после одобрения добавляем в contacts обе стороны
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS friend_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      from_user_id INTEGER NOT NULL,
      to_user_id INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(from_user_id, to_user_id),
      FOREIGN KEY (from_user_id) REFERENCES users(id),
      FOREIGN KEY (to_user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id);
    CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id);
    CREATE INDEX IF NOT EXISTS idx_friend_requests_to_status ON friend_requests(to_user_id, status);
    CREATE INDEX IF NOT EXISTS idx_friend_requests_from_to ON friend_requests(from_user_id, to_user_id);
  `);
} catch (_) {}

try { db.exec('ALTER TABLE messages ADD COLUMN attachment_path TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN attachment_filename TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN bio TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN avatar_path TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN public_key TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN message_type TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN poll_id INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN attachment_kind TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN attachment_duration_sec INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN attachment_encrypted INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN reply_to_id INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN is_forwarded INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN forward_from_sender_id INTEGER'); } catch (_) {}
try { db.exec('ALTER TABLE messages ADD COLUMN forward_from_display_name TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN email TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN birthday TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN phone TEXT'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN last_seen DATETIME'); } catch (_) {}
try { db.exec('ALTER TABLE users ADD COLUMN is_online INTEGER DEFAULT 0'); } catch (_) {}

db.exec(`
  CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
  );
  CREATE INDEX IF NOT EXISTS idx_reset_tokens_user ON password_reset_tokens(user_id);
  CREATE INDEX IF NOT EXISTS idx_reset_tokens_expires ON password_reset_tokens(expires_at);
  CREATE INDEX IF NOT EXISTS idx_reset_tokens_user_expires ON password_reset_tokens(user_id, expires_at);
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS polls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id INTEGER NOT NULL UNIQUE,
    question TEXT NOT NULL,
    options TEXT NOT NULL,
    multiple INTEGER DEFAULT 0,
    FOREIGN KEY (message_id) REFERENCES messages(id)
  );
  CREATE TABLE IF NOT EXISTS poll_votes (
    poll_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    option_index INTEGER NOT NULL,
    PRIMARY KEY (poll_id, user_id, option_index),
    FOREIGN KEY (poll_id) REFERENCES polls(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
  );
  CREATE INDEX IF NOT EXISTS idx_poll_votes_poll ON poll_votes(poll_id);
  CREATE INDEX IF NOT EXISTS idx_poll_votes_user ON poll_votes(user_id);
  CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_user ON poll_votes(poll_id, user_id);
`);

// Групповые чаты
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      avatar_path TEXT,
      created_by_user_id INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (created_by_user_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS group_members (
      group_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      role TEXT NOT NULL DEFAULT 'member',
      joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (group_id, user_id),
      FOREIGN KEY (group_id) REFERENCES groups(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
    CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
    CREATE INDEX IF NOT EXISTS idx_group_members_group_user ON group_members(group_id, user_id);
    CREATE TABLE IF NOT EXISTS group_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL,
      sender_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      attachment_path TEXT,
      attachment_filename TEXT,
      message_type TEXT DEFAULT 'text',
      attachment_kind TEXT DEFAULT 'file',
      attachment_duration_sec INTEGER,
      attachment_encrypted INTEGER DEFAULT 0,
      reply_to_id INTEGER,
      is_forwarded INTEGER DEFAULT 0,
      forward_from_sender_id INTEGER,
      forward_from_display_name TEXT,
      FOREIGN KEY (group_id) REFERENCES groups(id),
      FOREIGN KEY (sender_id) REFERENCES users(id),
      FOREIGN KEY (reply_to_id) REFERENCES group_messages(id)
    );
    
    -- Полнотекстовый поиск для групповых сообщений
    CREATE VIRTUAL TABLE IF NOT EXISTS group_messages_fts USING fts5(
      content,
      content='group_messages',
      content_rowid='id'
    );
    CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages(group_id);
    CREATE INDEX IF NOT EXISTS idx_group_messages_created ON group_messages(created_at);
    CREATE INDEX IF NOT EXISTS idx_group_messages_group_created ON group_messages(group_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_group_messages_sender ON group_messages(sender_id);
    CREATE TABLE IF NOT EXISTS group_read (
      group_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      last_read_message_id INTEGER NOT NULL,
      PRIMARY KEY (group_id, user_id),
      FOREIGN KEY (group_id) REFERENCES groups(id),
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (last_read_message_id) REFERENCES group_messages(id)
    );
    CREATE TABLE IF NOT EXISTS group_polls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_message_id INTEGER NOT NULL UNIQUE,
      question TEXT NOT NULL,
      options TEXT NOT NULL,
      multiple INTEGER DEFAULT 0,
      FOREIGN KEY (group_message_id) REFERENCES group_messages(id)
    );
    CREATE TABLE IF NOT EXISTS group_poll_votes (
      group_poll_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      option_index INTEGER NOT NULL,
      PRIMARY KEY (group_poll_id, user_id, option_index),
      FOREIGN KEY (group_poll_id) REFERENCES group_polls(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
  `);
} catch (err) {
  // Игнорируем ошибки при создании таблиц групп (миграция исправит структуру)
  log.warn({ error: err }, 'Ошибка при создании таблиц групп, миграция исправит структуру');
}

// Создаем индексы для group_poll_votes отдельно, чтобы не падать при старой структуре
// Проверяем, существует ли колонка group_poll_id перед созданием индексов
try {
  // Проверяем структуру таблицы через pragma_table_info
  const tableInfo = db.prepare(`PRAGMA table_info(group_poll_votes)`).all();
  const hasGroupPollId = tableInfo.some(col => col.name === 'group_poll_id');
  
  if (hasGroupPollId) {
    // Таблица имеет правильную структуру, создаем индексы
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
      CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
      CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
    `);
  } else {
    // Таблица имеет старую структуру, индексы будут созданы миграцией
    log.warn('Таблица group_poll_votes имеет старую структуру, индексы будут созданы миграцией');
  }
} catch (err) {
  // Игнорируем ошибки при создании индексов (таблица может иметь старую структуру)
  // Миграция исправит это позже
  log.warn({ error: err }, 'Ошибка при создании индексов для group_poll_votes, миграция исправит структуру');
}

// Реакции на сообщения (личные и групповые)
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS message_reactions (
      message_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      emoji TEXT NOT NULL,
      PRIMARY KEY (message_id, user_id),
      FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON message_reactions(message_id);
    CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON message_reactions(user_id);
  `);
} catch (_) {}
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS group_message_reactions (
      group_message_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      emoji TEXT NOT NULL,
      PRIMARY KEY (group_message_id, user_id),
      FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
    CREATE INDEX IF NOT EXISTS idx_group_message_reactions_msg ON group_message_reactions(group_message_id);
    CREATE INDEX IF NOT EXISTS idx_group_message_reactions_user ON group_message_reactions(user_id);
  `);
} catch (_) {}

export default db;

// Инициализация FTS индексов для существующих данных (отложенная, чтобы избежать циклической зависимости)
// Вызывается асинхронно после экспорта db
setImmediate(async () => {
  try {
    const { initFTSIndexes } = await import('./utils/ftsSync.js');
    initFTSIndexes();
  } catch (error) {
    log.warn({ error }, 'Не удалось инициализировать FTS индексы');
  }
});
