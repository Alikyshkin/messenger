import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import db from '../db.js';
import { signToken, authMiddleware } from '../auth.js';
import { sendPasswordResetEmail } from '../mailer.js';

const router = Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.post('/register', (req, res) => {
  const { username, password, displayName, email } = req.body;
  if (!username?.trim() || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }
  if (username.length < 3) {
    return res.status(400).json({ error: 'Username must be at least 3 characters' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  const emailTrim = typeof email === 'string' ? email.trim().toLowerCase() : null;
  if (emailTrim && !EMAIL_RE.test(emailTrim)) {
    return res.status(400).json({ error: 'Invalid email format' });
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
      return res.status(409).json({ error: 'Username already taken' });
    }
    throw e;
  }
});

router.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }
  const user = db.prepare(
    'SELECT id, username, display_name, email, password_hash FROM users WHERE username = ?'
  ).get(username.trim().toLowerCase());
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'Invalid username or password' });
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
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;
  const emailTrim = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!emailTrim) {
    return res.status(400).json({ error: 'Email required' });
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
  res.json({ message: 'If an account with this email exists, you will receive a reset link.' });
});

// Сброс пароля по токену из ссылки
router.post('/reset-password', (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || typeof token !== 'string' || !newPassword) {
    return res.status(400).json({ error: 'Token and new password required' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }
  const tokenHash = crypto.createHash('sha256').update(token.trim()).digest('hex');
  const row = db.prepare(
    'SELECT id, user_id FROM password_reset_tokens WHERE token_hash = ? AND expires_at > datetime(\'now\')'
  ).get(tokenHash);
  if (!row) {
    return res.status(400).json({ error: 'Invalid or expired reset link' });
  }
  const password_hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, row.user_id);
  db.prepare('DELETE FROM password_reset_tokens WHERE id = ?').run(row.id);
  res.json({ message: 'Password updated. You can now log in.' });
});

// Смена пароля (авторизованный пользователь)
router.post('/change-password', authMiddleware, (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'Current and new password required' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters' });
  }
  const user = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(req.user.userId);
  if (!user || !bcrypt.compareSync(currentPassword, user.password_hash)) {
    return res.status(401).json({ error: 'Current password is wrong' });
  }
  const password_hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, req.user.userId);
  res.json({ message: 'Password changed' });
});

export default router;
