/**
 * Проверка доступности БД для health/ready эндпоинтов.
 * @param {import('better-sqlite3').Database} db
 * @returns {{ ok: true } | { ok: false; error?: Error }}
 */
export function checkDatabase(db) {
  try {
    const result = db.prepare('SELECT 1').get();
    if (!result) {
      return { ok: false };
    }
    return { ok: true };
  } catch (error) {
    return { ok: false, error };
  }
}
