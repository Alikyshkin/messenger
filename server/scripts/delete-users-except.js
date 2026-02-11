#!/usr/bin/env node

/**
 * Скрипт для удаления всех пользователей кроме указанных
 * Использование: node scripts/delete-users-except.js azalia alika
 * ВНИМАНИЕ: Это удалит всех пользователей кроме указанных!
 */

import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, unlinkSync } from 'fs';

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

  // Удаляем данные для каждого пользователя
  for (const user of usersToDelete) {
    const userId = user.id;
    console.log(`Удаление пользователя: @${user.username} (ID: ${userId})...`);

    try {
      // Удаляем голоса в опросах
      db.prepare('DELETE FROM poll_votes WHERE user_id = ?').run(userId);
      db.prepare('DELETE FROM group_poll_votes WHERE user_id = ?').run(userId);

      // Удаляем опросы, созданные пользователем (через сообщения)
      const msgIds = db.prepare('SELECT id FROM messages WHERE sender_id = ? OR receiver_id = ?').all(userId, userId).map(r => r.id);
      if (msgIds.length > 0) {
        const msgPlaceholders = msgIds.map(() => '?').join(',');
        const pollIds = db.prepare(`SELECT id FROM polls WHERE message_id IN (${msgPlaceholders})`).all(...msgIds).map(r => r.id);
        if (pollIds.length > 0) {
          const pollPlaceholders = pollIds.map(() => '?').join(',');
          db.prepare(`DELETE FROM poll_votes WHERE poll_id IN (${pollPlaceholders})`).run(...pollIds);
          db.prepare(`DELETE FROM polls WHERE id IN (${pollPlaceholders})`).run(...pollIds);
        }
      }

      // Удаляем групповые опросы
      const groupMsgIds = db.prepare('SELECT id FROM group_messages WHERE sender_id = ?').all(userId).map(r => r.id);
      if (groupMsgIds.length > 0) {
        const groupMsgPlaceholders = groupMsgIds.map(() => '?').join(',');
        const groupPollIds = db.prepare(`SELECT id FROM group_polls WHERE group_message_id IN (${groupMsgPlaceholders})`).all(...groupMsgIds).map(r => r.id);
        if (groupPollIds.length > 0) {
          const groupPollPlaceholders = groupPollIds.map(() => '?').join(',');
          db.prepare(`DELETE FROM group_poll_votes WHERE group_poll_id IN (${groupPollPlaceholders})`).run(...groupPollIds);
          db.prepare(`DELETE FROM group_polls WHERE id IN (${groupPollPlaceholders})`).run(...groupPollIds);
        }
      }

      // Удаляем реакции
      db.prepare('DELETE FROM message_reactions WHERE user_id = ?').run(userId);
      db.prepare('DELETE FROM group_message_reactions WHERE user_id = ?').run(userId);

      // Удаляем прочитанные сообщения в группах
      db.prepare('DELETE FROM group_read WHERE user_id = ?').run(userId);

      // Удаляем групповые сообщения
      db.prepare('DELETE FROM group_messages WHERE sender_id = ?').run(userId);

      // Удаляем участников групп
      db.prepare('DELETE FROM group_members WHERE user_id = ?').run(userId);

      // Удаляем группы, созданные пользователем (если они остались без участников)
      const groupsCreated = db.prepare('SELECT id FROM groups WHERE created_by_user_id = ?').all(userId).map(r => r.id);
      for (const groupId of groupsCreated) {
        const memberCount = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(groupId)?.c ?? 0;
        if (memberCount === 0) {
          db.prepare('DELETE FROM group_messages WHERE group_id = ?').run(groupId);
          db.prepare('DELETE FROM groups WHERE id = ?').run(groupId);
        }
      }

      // Удаляем сообщения
      db.prepare('DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?').run(userId, userId);

      // Удаляем контакты
      db.prepare('DELETE FROM contacts WHERE user_id = ? OR contact_id = ?').run(userId, userId);

      // Удаляем заявки в друзья
      db.prepare('DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?').run(userId, userId);

      // Удаляем FCM токены
      db.prepare('DELETE FROM user_fcm_tokens WHERE user_id = ?').run(userId);

      // Удаляем токены сброса пароля
      db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(userId);

      // Удаляем audit logs (опционально)
      db.prepare('DELETE FROM audit_logs WHERE user_id = ?').run(userId);

      // Удаляем аватар пользователя
      if (user.avatar_path) {
        const avatarsDir = join(__dirname, '../uploads/avatars');
        const fullPath = join(avatarsDir, user.avatar_path);
        if (existsSync(fullPath)) {
          try {
            unlinkSync(fullPath);
          } catch (err) {
            console.log(`  ⚠ Не удалось удалить аватар: ${err.message}`);
          }
        }
      }

      // Удаляем пользователя
      db.prepare('DELETE FROM users WHERE id = ?').run(userId);

      console.log(`  ✓ Пользователь @${user.username} удален`);
    } catch (err) {
      console.error(`  ❌ Ошибка при удалении пользователя @${user.username}: ${err.message}`);
    }
  }

  // Очищаем FTS индексы для удаленных сообщений
  console.log('\nОчистка FTS индексов...');
  try {
    db.prepare('DELETE FROM messages_fts WHERE rowid NOT IN (SELECT id FROM messages)').run();
    db.prepare('DELETE FROM group_messages_fts WHERE rowid NOT IN (SELECT id FROM group_messages)').run();
  } catch (err) {
    console.log(`  ⚠ Ошибка при очистке FTS индексов: ${err.message}`);
  }

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
