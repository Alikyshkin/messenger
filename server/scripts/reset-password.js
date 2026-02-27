#!/usr/bin/env node

/**
 * Скрипт для сброса пароля пользователя
 * Использование: node scripts/reset-password.js <username> <new_password>
 */

import Database from 'better-sqlite3';
import bcrypt from 'bcryptjs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const username = process.argv[2]?.toLowerCase().trim();
const newPassword = process.argv[3];

if (!username || !newPassword) {
  console.error('Ошибка: Укажите username и новый пароль');
  console.log('Использование: node scripts/reset-password.js <username> <new_password>');
  process.exit(1);
}

if (newPassword.length < 6) {
  console.error('Ошибка: Пароль должен быть не менее 6 символов');
  process.exit(1);
}

const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db');

const db = new Database(dbPath);

try {
  const user = db.prepare('SELECT id, username FROM users WHERE LOWER(username) = ?').get(username);

  if (!user) {
    console.error(`Пользователь @${username} не найден`);
    db.close();
    process.exit(1);
  }

  const hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(hash, user.id);

  console.log(`Пароль пользователя @${user.username} успешно обновлён`);
  db.close();
  process.exit(0);
} catch (error) {
  console.error('Ошибка:', error.message);
  db.close();
  process.exit(1);
}
