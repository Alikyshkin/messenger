import db from '../db.js';
import { log } from './logger.js';

const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 минут

/**
 * Проверить, заблокирован ли аккаунт
 */
export function isAccountLocked(userId) {
  const lockout = db.prepare(`
    SELECT locked_until 
    FROM users 
    WHERE id = ? AND locked_until IS NOT NULL AND locked_until > datetime('now')
  `).get(userId);
  
  return !!lockout;
}

/**
 * Получить оставшееся время блокировки в секундах
 */
export function getLockoutRemainingSeconds(userId) {
  const lockout = db.prepare(`
    SELECT locked_until 
    FROM users 
    WHERE id = ? AND locked_until IS NOT NULL AND locked_until > datetime('now')
  `).get(userId);
  
  if (!lockout) {
    return 0;
  }
  
  const lockedUntil = new Date(lockout.locked_until);
  const now = new Date();
  const remaining = Math.ceil((lockedUntil - now) / 1000);
  
  return remaining > 0 ? remaining : 0;
}

/**
 * Зарегистрировать неудачную попытку входа
 */
export function recordFailedAttempt(userId, username) {
  // Увеличиваем счетчик неудачных попыток
  const result = db.prepare(`
    UPDATE users 
    SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
        last_failed_login = datetime('now')
    WHERE id = ?
  `).run(userId);
  
  if (result.changes === 0) {
    // Пользователь не найден, создаём запись о попытке по username
    const user = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
    if (user) {
      db.prepare(`
        UPDATE users 
        SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
            last_failed_login = datetime('now')
        WHERE id = ?
      `).run(user.id);
    }
    return;
  }
  
  // Проверяем, нужно ли заблокировать аккаунт
  const user = db.prepare('SELECT failed_login_attempts FROM users WHERE id = ?').get(userId);
  if (user && user.failed_login_attempts >= MAX_FAILED_ATTEMPTS) {
    const lockedUntil = new Date(Date.now() + LOCKOUT_DURATION_MS);
    db.prepare(`
      UPDATE users 
      SET locked_until = ?
      WHERE id = ?
    `).run(lockedUntil.toISOString(), userId);
    
    log.warn({ userId, username, lockedUntil }, 'Account locked due to failed login attempts');
  }
}

/**
 * Сбросить счетчик неудачных попыток после успешного входа
 */
export function resetFailedAttempts(userId) {
  db.prepare(`
    UPDATE users 
    SET failed_login_attempts = 0,
        locked_until = NULL,
        last_failed_login = NULL
    WHERE id = ?
  `).run(userId);
}

/**
 * Middleware для проверки блокировки аккаунта
 */
export function checkAccountLockout(req, res, next) {
  const { username } = req.body;
  
  if (!username) {
    return next();
  }
  
  // Нормализуем username так же, как в auth route
  const normalizedUsername = username.trim().toLowerCase();
  const user = db.prepare('SELECT id, locked_until FROM users WHERE username = ?').get(normalizedUsername);
  
  if (!user) {
    return next(); // Пользователь не найден, проверка будет в auth route
  }
  
  if (isAccountLocked(user.id)) {
    const remaining = getLockoutRemainingSeconds(user.id);
    log.warn({ userId: user.id, username: normalizedUsername, remaining }, 'Login attempt on locked account');
    
    return res.status(423).json({
      error: 'Аккаунт временно заблокирован из-за множественных неудачных попыток входа',
      lockedUntil: user.locked_until,
      remainingSeconds: remaining,
    });
  }
  
  next();
}
