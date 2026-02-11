import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import db from '../db.js';
import { signToken, authMiddleware } from '../auth.js';
import { sendPasswordResetEmail } from '../mailer.js';
import { authLimiter, registerLimiter, passwordResetLimiter } from '../middleware/rateLimit.js';

const router = Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.post('/register', registerLimiter, (req, res) => {
  const { username, password, displayName, email } = req.body;
  if (!username?.trim() || !password) {
    return res.status(400).json({ error: 'Укажите имя пользователя и пароль' });
  }
  if (username.length < 3) {
    return res.status(400).json({ error: 'Имя пользователя минимум 3 символа' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Пароль минимум 6 символов' });
  }
  const emailTrim = typeof email === 'string' ? email.trim().toLowerCase() : null;
  if (emailTrim && !EMAIL_RE.test(emailTrim)) {
    return res.status(400).json({ error: 'Некорректный формат email' });
  }
  const password_hash = bcrypt.hashSync(password, 10);
  try {
    const result = db.prepare(
      'INSERT INTO users (username, display_name, password_hash, email) VALUES (?, ?, ?, ?)'
    ).run(username.trim().toLowerCase(), (displayName || username).trim() || null, password_hash, emailTrim || null);
    const user = db.prepare('SELECT id, username, display_name, email, created_at FROM users WHERE id = ?')
      .get(result.lastInsertRowid);
    const token = signToken(user.id, user.username);
    res.status(201).json({
      user: {
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        email: user.email || null,
      },
      token,
    });
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json({ error: 'Это имя пользователя уже занято' });
    }
    throw e;
  }
});

router.post('/login', authLimiter, (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Укажите имя пользователя и пароль' });
  }
  const user = db.prepare(
    'SELECT id, username, display_name, email, password_hash FROM users WHERE username = ?'
  ).get(username.trim().toLowerCase());
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'Неверное имя пользователя или пароль' });
  }
  const token = signToken(user.id, user.username);
  res.json({
    user: {
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      email: user.email || null,
    },
    token,
  });
});

// Восстановление пароля: запрос письма со ссылкой
router.post('/forgot-password', passwordResetLimiter, async (req, res) => {
  const { email } = req.body;
  const emailTrim = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!emailTrim) {
    return res.status(400).json({ error: 'Укажите email' });
  }
  const user = db.prepare('SELECT id FROM users WHERE email = ?').get(emailTrim);
  if (user) {
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // 1 час
    db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(user.id);
    db.prepare(
      'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)'
    ).run(user.id, tokenHash, expiresAt);
    await sendPasswordResetEmail(emailTrim, token);
  }
  res.json({ message: 'Если аккаунт с таким email существует, на него отправлена ссылка для сброса пароля.' });
});

// Сброс пароля по токену из ссылки
router.post('/reset-password', passwordResetLimiter, (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || typeof token !== 'string' || !newPassword) {
    return res.status(400).json({ error: 'Укажите токен и новый пароль' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'Пароль минимум 6 символов' });
  }
  const tokenHash = crypto.createHash('sha256').update(token.trim()).digest('hex');
  const row = db.prepare(
    'SELECT id, user_id FROM password_reset_tokens WHERE token_hash = ? AND expires_at > datetime(\'now\')'
  ).get(tokenHash);
  if (!row) {
    return res.status(400).json({ error: 'Ссылка недействительна или истекла' });
  }
  const password_hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, row.user_id);
  db.prepare('DELETE FROM password_reset_tokens WHERE id = ?').run(row.id);
  res.json({ message: 'Пароль обновлён. Теперь можно войти.' });
});

// Смена пароля (авторизованный пользователь)
router.post('/change-password', authMiddleware, (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'Укажите текущий и новый пароль' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'Новый пароль минимум 6 символов' });
  }
  const user = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(req.user.userId);
  if (!user || !bcrypt.compareSync(currentPassword, user.password_hash)) {
    return res.status(401).json({ error: 'Неверный текущий пароль' });
  }
  const password_hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, req.user.userId);
  res.json({ message: 'Пароль изменён' });
});

export default router;
