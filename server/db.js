import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, 'messenger.db');
const db = new Database(dbPath);

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

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

  CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
  CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
  CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
  CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id);
`);

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
try { db.exec('ALTER TABLE users ADD COLUMN email TEXT'); } catch (_) {}

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
`);

export default db;
