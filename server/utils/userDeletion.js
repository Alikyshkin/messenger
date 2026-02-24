/**
 * Каскадное удаление пользователя: все связанные данные в БД и опционально файл аватара.
 * Используется в DELETE /users/me (роут) и в скрипте delete-users-except.js.
 */

import { existsSync, unlinkSync } from 'fs';
import path from 'path';

/**
 * Выполняет каскадное удаление пользователя из БД (порядок с учётом зависимостей).
 * @param {object} db - экземпляр better-sqlite3 Database
 * @param {number} userId - ID пользователя
 * @param {{ avatarsDir?: string, onWarning?: (message: string) => void }} options
 *   - avatarsDir: путь к папке аватаров — если передан, файл аватара пользователя удаляется с диска
 *   - onWarning: опциональный callback для некритичных предупреждений (например, отсутствие таблицы опросов)
 */
export function deleteUserCascade(db, userId, options = {}) {
  const { avatarsDir, onWarning } = options;

  // Аватар нужен до удаления записи пользователя
  let avatarPath = null;
  if (avatarsDir) {
    const row = db.prepare('SELECT avatar_path FROM users WHERE id = ?').get(userId);
    avatarPath = row?.avatar_path ?? null;
  }

  // Голоса в опросах (личные и групповые)
  db.prepare('DELETE FROM poll_votes WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM group_poll_votes WHERE user_id = ?').run(userId);

  // Опросы в личных сообщениях (созданные пользователем или в диалоге с ним)
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
      onWarning?.(`Удаление опросов в личных сообщениях: ${err.message}`);
    }
  }

  // Групповые опросы в сообщениях пользователя
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
      onWarning?.(`Удаление групповых опросов: ${err.message}`);
    }
  }

  // Реакции
  db.prepare('DELETE FROM message_reactions WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM group_message_reactions WHERE user_id = ?').run(userId);

  // Прочитанные сообщения в группах
  db.prepare('DELETE FROM group_read WHERE user_id = ?').run(userId);

  // Групповые сообщения пользователя
  db.prepare('DELETE FROM group_messages WHERE sender_id = ?').run(userId);

  // Участник групп
  db.prepare('DELETE FROM group_members WHERE user_id = ?').run(userId);

  // Группы, созданные пользователем, если остались без участников
  const groupsCreated = db.prepare('SELECT id FROM groups WHERE created_by_user_id = ?').all(userId).map(r => r.id);
  for (const groupId of groupsCreated) {
    const memberCount = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(groupId)?.c ?? 0;
    if (memberCount === 0) {
      db.prepare('DELETE FROM group_messages WHERE group_id = ?').run(groupId);
      db.prepare('DELETE FROM groups WHERE id = ?').run(groupId);
    }
  }

  // Личные сообщения
  db.prepare('DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?').run(userId, userId);

  // Контакты и заявки в друзья
  db.prepare('DELETE FROM contacts WHERE user_id = ? OR contact_id = ?').run(userId, userId);
  db.prepare('DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?').run(userId, userId);

  // FCM, токены сброса пароля, аудит
  db.prepare('DELETE FROM user_fcm_tokens WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM audit_logs WHERE user_id = ?').run(userId);

  // Приватность и блокировки
  db.prepare('DELETE FROM user_privacy WHERE user_id = ?').run(userId);
  db.prepare('DELETE FROM user_privacy_hide_from WHERE user_id = ? OR hidden_from_user_id = ?').run(userId, userId);
  db.prepare('DELETE FROM blocked_users WHERE blocker_id = ? OR blocked_id = ?').run(userId, userId);

  // Запись пользователя
  db.prepare('DELETE FROM users WHERE id = ?').run(userId);

  // Файл аватара с диска
  if (avatarsDir && avatarPath) {
    const fullPath = path.join(avatarsDir, avatarPath);
    if (existsSync(fullPath)) {
      try {
        unlinkSync(fullPath);
      } catch (err) {
        onWarning?.(`Не удалось удалить аватар: ${err.message}`);
      }
    }
  }
}
