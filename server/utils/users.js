/**
 * Утилиты для работы с пользователями.
 */

/**
 * Возвращает отображаемое имя пользователя: display_name || username || fallback.
 * @param {import('better-sqlite3').Database} db
 * @param {number} userId
 * @param {string} [fallback='User']
 * @returns {string}
 */
export function getUserDisplayName(db, userId, fallback = 'User') {
  const user = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(userId);
  return displayNameFromUser(user, fallback);
}

/**
 * Возвращает отображаемое имя из уже загруженного объекта пользователя.
 * @param {{ display_name?: string | null; username?: string } | null | undefined} user
 * @param {string} [fallback='?']
 * @returns {string}
 */
export function displayNameFromUser(user, fallback = '?') {
  return user?.display_name || user?.username || fallback;
}
