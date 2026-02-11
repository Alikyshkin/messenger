#!/usr/bin/env node

/**
 * Скрипт для удаления одного пользователя по username
 * Использование: node scripts/delete-user.js alikyshkin_
 */

import Database from 'better-sqlite3';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, unlinkSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const usernameToDelete = process.argv[2]?.toLowerCase().trim();

if (!usernameToDelete) {
  console.error('❌ Ошибка: Не указан username для удаления!');
  console.log('Использование: node scripts/delete-user.js username');
  process.exit(1);
}

const dbPath = process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db');

console.log(`⚠️  ВНИМАНИЕ: Это удалит пользователя @${usernameToDelete} и все его данные!`);
console.log(`База данных: ${dbPath}\n`);

const db = new Database(dbPath);
db.pragma('foreign_keys = OFF');

try {
  // Находим пользователя
  const user = db.prepare('SELECT id, username, avatar_path FROM users WHERE LOWER(username) = LOWER(?)').get(usernameToDelete);
  
  if (!user) {
    console.error(`❌ Пользователь @${usernameToDelete} не найден в базе данных!`);
    db.close();
    process.exit(1);
  }

  const userId = user.id;
  console.log(`Найден пользователь: @${user.username} (ID: ${userId})`);
  console.log('Начинаю удаление...\n');

  try {
    // Удаляем голоса в опросах
    db.prepare('DELETE FROM poll_votes WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM group_poll_votes WHERE user_id = ?').run(userId);

    // Удаляем опросы через сообщения (с обработкой ошибок)
    const msgIds = db.prepare('SELECT id FROM messages WHERE sender_id = ? OR receiver_id = ?').all(userId, userId).map(r => r.id);
    if (msgIds.length > 0) {
      const msgPlaceholders = msgIds.map(() => '?').join(',');
      try {
        const pollIds = db.prepare(`SELECT id FROM polls WHERE message_id IN (${msgPlaceholders})`).all(...msgIds).map(r => r.id);
        if (pollIds.length > 0) {
          const pollPlaceholders = pollIds.map(() => '?').join(',');
          db.prepare(`DELETE FROM poll_votes WHERE poll_id IN (${pollPlaceholders})`).run(...pollIds);
          db.prepare(`DELETE FROM polls WHERE id IN (${pollPlaceholders})`).run(...pollIds);
        }
      } catch (err) {
        console.log(`  ⚠ Предупреждение при удалении опросов: ${err.message}`);
      }
    }

    // Удаляем групповые опросы
    const groupMsgIds = db.prepare('SELECT id FROM group_messages WHERE sender_id = ?').all(userId).map(r => r.id);
    if (groupMsgIds.length > 0) {
      const groupMsgPlaceholders = groupMsgIds.map(() => '?').join(',');
      try {
        const groupPollIds = db.prepare(`SELECT id FROM group_polls WHERE group_message_id IN (${groupMsgPlaceholders})`).all(...groupMsgIds).map(r => r.id);
        if (groupPollIds.length > 0) {
          const groupPollPlaceholders = groupPollIds.map(() => '?').join(',');
          db.prepare(`DELETE FROM group_poll_votes WHERE group_poll_id IN (${groupPollPlaceholders})`).run(...groupPollIds);
          db.prepare(`DELETE FROM group_polls WHERE id IN (${groupPollPlaceholders})`).run(...groupPollIds);
        }
      } catch (err) {
        console.log(`  ⚠ Предупреждение при удалении групповых опросов: ${err.message}`);
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

    // Удаляем группы, созданные пользователем
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

    // Удаляем audit logs
    db.prepare('DELETE FROM audit_logs WHERE user_id = ?').run(userId);

    // Удаляем аватар
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

    console.log(`\n✅ Пользователь @${user.username} успешно удален!`);

  } catch (err) {
    console.error(`\n❌ Ошибка при удалении пользователя: ${err.message}`);
    throw err;
  }

  db.pragma('foreign_keys = ON');
  db.close();
  process.exit(0);
} catch (error) {
  console.error('\n❌ Ошибка:', error);
  db.pragma('foreign_keys = ON');
  db.close();
  process.exit(1);
}
