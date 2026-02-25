/**
 * Утилиты для работы с контактами.
 */

/**
 * Возвращает массив ID контактов пользователя (взаимные контакты).
 * @param {import('better-sqlite3').Database} db
 * @param {number} userId
 * @returns {number[]}
 */
export function getContactIds(db, userId) {
  return db.prepare('SELECT contact_id FROM contacts WHERE user_id = ?').all(userId).map((r) => r.contact_id);
}
