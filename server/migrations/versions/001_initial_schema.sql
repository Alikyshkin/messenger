-- Миграция 001: Начальная схема базы данных
-- Эта миграция создаёт базовую структуру таблиц

-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  email TEXT,
  phone TEXT,
  public_key TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen DATETIME,
  is_online INTEGER DEFAULT 0
);

-- Таблица контактов
CREATE TABLE IF NOT EXISTS contacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  contact_id INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (contact_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, contact_id)
);

-- Таблица сообщений
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender_id INTEGER NOT NULL,
  receiver_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  read_at DATETIME,
  attachment_url TEXT,
  attachment_filename TEXT,
  attachment_kind TEXT,
  message_type TEXT DEFAULT 'text',
  reply_to_id INTEGER,
  FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL
);

-- Таблица групп
CREATE TABLE IF NOT EXISTS groups (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  avatar_url TEXT,
  created_by_user_id INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Таблица участников групп
CREATE TABLE IF NOT EXISTS group_members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  role TEXT DEFAULT 'member',
  joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(group_id, user_id)
);

-- Таблица сообщений в группах
CREATE TABLE IF NOT EXISTS group_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL,
  sender_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  attachment_url TEXT,
  attachment_filename TEXT,
  attachment_kind TEXT,
  message_type TEXT DEFAULT 'text',
  reply_to_id INTEGER,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (reply_to_id) REFERENCES group_messages(id) ON DELETE SET NULL
);

-- Таблица прочитанных сообщений в группах
CREATE TABLE IF NOT EXISTS group_read (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  message_id INTEGER NOT NULL,
  read_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES group_messages(id) ON DELETE CASCADE,
  UNIQUE(group_id, user_id, message_id)
);

-- Таблица реакций на сообщения
CREATE TABLE IF NOT EXISTS message_reactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  emoji TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(message_id, user_id)
);

-- Таблица реакций на сообщения в группах
CREATE TABLE IF NOT EXISTS group_message_reactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  emoji TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (message_id) REFERENCES group_messages(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(message_id, user_id)
);

-- Таблица опросов
CREATE TABLE IF NOT EXISTS polls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER NOT NULL,
  question TEXT NOT NULL,
  options TEXT NOT NULL, -- JSON массив строк
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  UNIQUE(message_id)
);

-- Таблица голосов в опросах
CREATE TABLE IF NOT EXISTS poll_votes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  poll_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  option_index INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (poll_id) REFERENCES polls(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(poll_id, user_id)
);

-- Таблица опросов в группах
CREATE TABLE IF NOT EXISTS group_polls (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id INTEGER NOT NULL,
  question TEXT NOT NULL,
  options TEXT NOT NULL, -- JSON массив строк
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (message_id) REFERENCES group_messages(id) ON DELETE CASCADE,
  UNIQUE(message_id)
);

-- Таблица голосов в опросах групп
CREATE TABLE IF NOT EXISTS group_poll_votes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  poll_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  option_index INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (poll_id) REFERENCES group_polls(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(poll_id, user_id)
);

-- Таблица токенов сброса пароля
CREATE TABLE IF NOT EXISTS reset_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  token TEXT NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Таблица заявок в друзья
CREATE TABLE IF NOT EXISTS friend_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_user_id INTEGER NOT NULL,
  to_user_id INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (to_user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(from_user_id, to_user_id)
);
