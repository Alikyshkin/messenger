#!/usr/bin/env node

/**
 * Скрипт для полной очистки базы данных (удаление всех пользователей и данных)
 * Использование: node scripts/reset-db.js
 * ВНИМАНИЕ: Это удалит ВСЕ данные из базы!
 */

import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Настраиваем путь к БД
const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db');

console.log('⚠️  ВНИМАНИЕ: Это удалит ВСЕ данные из базы данных!');
console.log(`База данных: ${dbPath}`);
console.log('Начинаю очистку...\n');

const db = new Database(dbPath);

// Включаем foreign keys для каскадного удаления
db.pragma('foreign_keys = ON');

try {
  // Удаляем все данные в правильном порядке (с учетом foreign keys)
  
  console.log('Удаление голосов в опросах...');
  db.prepare('DELETE FROM group_poll_votes').run();
  db.prepare('DELETE FROM poll_votes').run();
  
  console.log('Удаление опросов...');
  db.prepare('DELETE FROM group_polls').run();
  db.prepare('DELETE FROM polls').run();
  
  console.log('Удаление реакций...');
  db.prepare('DELETE FROM group_message_reactions').run();
  db.prepare('DELETE FROM message_reactions').run();
  
  console.log('Удаление прочитанных сообщений...');
  db.prepare('DELETE FROM group_read').run();
  
  console.log('Удаление групповых сообщений...');
  db.prepare('DELETE FROM group_messages').run();
  
  console.log('Удаление участников групп...');
  db.prepare('DELETE FROM group_members').run();
  
  console.log('Удаление групп...');
  db.prepare('DELETE FROM groups').run();
  
  console.log('Удаление сообщений...');
  db.prepare('DELETE FROM messages').run();
  
  console.log('Удаление заявок в друзья...');
  db.prepare('DELETE FROM friend_requests').run();
  
  console.log('Удаление контактов...');
  db.prepare('DELETE FROM contacts').run();
  
  console.log('Удаление FCM токенов...');
  db.prepare('DELETE FROM user_fcm_tokens').run();
  
  console.log('Удаление токенов сброса пароля...');
  db.prepare('DELETE FROM password_reset_tokens').run();
  
  console.log('Удаление audit logs...');
  db.prepare('DELETE FROM audit_logs').run();
  
  console.log('Удаление пользователей...');
  db.prepare('DELETE FROM users').run();
  
  // Очищаем FTS индексы
  console.log('Очистка FTS индексов...');
  try {
    db.prepare('DELETE FROM group_messages_fts').run();
  } catch (_) {}
  try {
    db.prepare('DELETE FROM messages_fts').run();
  } catch (_) {}
  
  // Сбрасываем счетчики AUTOINCREMENT
  console.log('Сброс счетчиков...');
  db.prepare('DELETE FROM sqlite_sequence').run();
  
  console.log('\n✅ База данных успешно очищена!');
  console.log('Теперь вы можете зарегистрировать нового пользователя.');
  
  db.close();
  process.exit(0);
} catch (error) {
  console.error('\n❌ Ошибка при очистке базы данных:', error);
  db.close();
  process.exit(1);
}
