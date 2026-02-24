#!/usr/bin/env node

/**
 * Скрипт для удаления всех пользователей кроме указанных
 * Использование: node scripts/delete-users-except.js azalia alika
 * ВНИМАНИЕ: Это удалит всех пользователей кроме указанных!
 */

import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { deleteUserCascade } from '../utils/userDeletion.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Получаем список пользователей для сохранения из аргументов командной строки
const usersToKeep = process.argv.slice(2).map(u => u.toLowerCase().trim()).filter(Boolean);

if (usersToKeep.length === 0) {
  console.error('❌ Ошибка: Не указаны пользователи для сохранения!');
  console.log('Использование: node scripts/delete-users-except.js azalia alika');
  process.exit(1);
}

// Настраиваем путь к БД (используем тот же путь, что и в db.js)
const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db');

console.log('⚠️  ВНИМАНИЕ: Это удалит всех пользователей кроме указанных!');
console.log(`База данных: ${dbPath}`);
console.log(`Пользователи для сохранения: ${usersToKeep.join(', ')}\n`);

const db = new Database(dbPath);

// Отключаем foreign keys для безопасного удаления
db.pragma('foreign_keys = OFF');

try {
  // Находим ID пользователей для сохранения
  const keepUserIds = [];
  for (const username of usersToKeep) {
    const user = db.prepare('SELECT id, username FROM users WHERE LOWER(username) = LOWER(?)').get(username);
    if (user) {
      keepUserIds.push(user.id);
      console.log(`✓ Найден пользователь: @${user.username} (ID: ${user.id})`);
    } else {
      console.log(`⚠ Пользователь @${username} не найден в базе данных`);
    }
  }

  if (keepUserIds.length === 0) {
    console.error('❌ Ошибка: Не найдено ни одного пользователя для сохранения!');
    db.close();
    process.exit(1);
  }

  console.log(`\nНайдено пользователей для сохранения: ${keepUserIds.length}`);
  console.log(`Начинаю удаление остальных пользователей...\n`);

  // Получаем список всех пользователей для удаления
  const placeholders = keepUserIds.map(() => '?').join(',');
  const usersToDelete = db.prepare(`SELECT id, username, avatar_path FROM users WHERE id NOT IN (${placeholders})`).all(...keepUserIds);
  
  console.log(`Пользователей для удаления: ${usersToDelete.length}`);

  if (usersToDelete.length === 0) {
    console.log('✓ Нет пользователей для удаления');
    db.pragma('foreign_keys = ON');
    db.close();
    process.exit(0);
  }

  const avatarsDir = join(__dirname, '../uploads/avatars');

  for (const user of usersToDelete) {
    const userId = user.id;
    console.log(`Удаление пользователя: @${user.username} (ID: ${userId})...`);

    try {
      deleteUserCascade(db, userId, {
        avatarsDir,
        onWarning: (msg) => console.log(`  ⚠ ${msg}`),
      });
      console.log(`  ✓ Пользователь @${user.username} удален`);
    } catch (err) {
      console.error(`  ❌ Ошибка при удалении пользователя @${user.username}: ${err.message}`);
    }
  }

  // FTS индексы очищаются автоматически триггерами при удалении сообщений
  // Дополнительная очистка не требуется

  // Включаем foreign keys обратно
  db.pragma('foreign_keys = ON');

  console.log('\n✅ Удаление завершено!');
  console.log(`Сохранено пользователей: ${keepUserIds.length}`);
  console.log(`Удалено пользователей: ${usersToDelete.length}`);

  // Показываем оставшихся пользователей
  const remainingUsers = db.prepare('SELECT id, username, display_name FROM users ORDER BY username').all();
  console.log('\nОставшиеся пользователи:');
  for (const user of remainingUsers) {
    console.log(`  - @${user.username} (${user.display_name || 'без имени'})`);
  }

  db.close();
  process.exit(0);
} catch (error) {
  console.error('\n❌ Ошибка при удалении пользователей:', error);
  db.pragma('foreign_keys = ON');
  db.close();
  process.exit(1);
}
