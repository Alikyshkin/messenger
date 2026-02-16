import db from '../db.js';

/**
 * Проверяет, заблокирована ли коммуникация между двумя пользователями.
 * Возвращает true, если кто-то из них заблокировал другого.
 */
export function isCommunicationBlocked(userId1, userId2) {
  if (!userId1 || !userId2 || userId1 === userId2) return false;
  const row = db.prepare(
    'SELECT 1 FROM blocked_users WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)'
  ).get(userId1, userId2, userId2, userId1);
  return !!row;
}

/** Проверяет, заблокировал ли me пользователя other. */
export function isBlockedByMe(me, other) {
  if (!me || !other) return false;
  const row = db.prepare('SELECT 1 FROM blocked_users WHERE blocker_id = ? AND blocked_id = ?').get(me, other);
  return !!row;
}
