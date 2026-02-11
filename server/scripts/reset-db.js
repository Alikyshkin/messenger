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

// Отключаем foreign keys для безопасного удаления всех данных
db.pragma('foreign_keys = OFF');

try {
  // Удаляем все данные в правильном порядке
  // Используем try-catch для каждой операции, чтобы пропускать несуществующие таблицы
  
  const deleteTable = (tableName) => {
    try {
      db.prepare(`DELETE FROM ${tableName}`).run();
      return true;
    } catch (err) {
      // Игнорируем ошибки для несуществующих таблиц
      return false;
    }
  };
  
  console.log('Удаление голосов в опросах...');
  deleteTable('group_poll_votes');
  deleteTable('poll_votes');
  
  console.log('Удаление опросов...');
  deleteTable('group_polls');
  deleteTable('polls');
  
  console.log('Удаление реакций...');
  deleteTable('group_message_reactions');
  deleteTable('message_reactions');
  
  console.log('Удаление прочитанных сообщений...');
  deleteTable('group_read');
  
  console.log('Удаление групповых сообщений...');
  deleteTable('group_messages');
  
  console.log('Удаление участников групп...');
  deleteTable('group_members');
  
  console.log('Удаление групп...');
  deleteTable('groups');
  
  console.log('Удаление сообщений...');
  deleteTable('messages');
  
  console.log('Удаление заявок в друзья...');
  deleteTable('friend_requests');
  
  console.log('Удаление контактов...');
  deleteTable('contacts');
  
  console.log('Удаление FCM токенов...');
  deleteTable('user_fcm_tokens');
  
  console.log('Удаление токенов сброса пароля...');
  deleteTable('password_reset_tokens');
  
  console.log('Удаление audit logs...');
  deleteTable('audit_logs');
  
  console.log('Удаление пользователей...');
  deleteTable('users');
  
  // Очищаем FTS индексы
  console.log('Очистка FTS индексов...');
  deleteTable('group_messages_fts');
  deleteTable('messages_fts');
  
  // Сбрасываем счетчики AUTOINCREMENT
  console.log('Сброс счетчиков...');
  try {
    db.prepare('DELETE FROM sqlite_sequence').run();
  } catch (_) {}
  
  // Включаем foreign keys обратно
  db.pragma('foreign_keys = ON');
  
  console.log('\n✅ База данных успешно очищена!');
  console.log('Теперь вы можете зарегистрировать нового пользователя.');
  
  db.close();
  process.exit(0);
} catch (error) {
  console.error('\n❌ Ошибка при очистке базы данных:', error);
  db.close();
  process.exit(1);
}
