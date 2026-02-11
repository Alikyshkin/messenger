import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import db from '../db.js';
import { signToken, authMiddleware } from '../auth.js';
import { sendPasswordResetEmail } from '../mailer.js';
import { authLimiter, registerLimiter, passwordResetLimiter } from '../middleware/rateLimit.js';
import { validate, registerSchema, loginSchema, forgotPasswordSchema, resetPasswordSchema, changePasswordSchema } from '../middleware/validation.js';
import { log } from '../utils/logger.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { auditLog, AUDIT_EVENTS } from '../utils/auditLog.js';

const router = Router();

/**
 * @swagger
 * /auth/register:
 *   post:
 *     summary: Регистрация нового пользователя
 *     tags: [Authentication]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - username
 *               - password
 *             properties:
 *               username:
 *                 type: string
 *                 minLength: 3
 *                 maxLength: 50
 *               password:
 *                 type: string
 *                 minLength: 6
 *                 maxLength: 128
 *               displayName:
 *                 type: string
 *                 maxLength: 100
 *               email:
 *                 type: string
 *                 format: email
 *     responses:
 *       201:
 *         description: Пользователь успешно зарегистрирован
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 user:
 *                   $ref: '#/components/schemas/User'
 *                 token:
 *                   type: string
 *       400:
 *         description: Ошибка валидации
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       409:
 *         description: Имя пользователя уже занято
 */
router.post('/register', registerLimiter, validate(registerSchema), asyncHandler(async (req, res) => {
  const { username, password, displayName, email } = req.validated;
  const normalizedUsername = username.trim().toLowerCase();
  const password_hash = bcrypt.hashSync(password, 10);
  try {
    const result = db.prepare(
      'INSERT INTO users (username, display_name, password_hash, email) VALUES (?, ?, ?, ?)'
    ).run(normalizedUsername, (displayName || username) || null, password_hash, email || null);
    const user = db.prepare('SELECT id, username, display_name, email, created_at FROM users WHERE id = ?')
      .get(result.lastInsertRowid);
    const token = signToken(user.id, user.username);
    
    // Audit log
    auditLog(AUDIT_EVENTS.REGISTER, user.id, {
      ip: req.ip || req.connection?.remoteAddress,
      userAgent: req.get('user-agent'),
      username: user.username,
    });
    
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
    log.error('Registration error', e, { username });
    throw e;
  }
}));

/**
 * @swagger
 * /auth/login:
 *   post:
 *     summary: Вход в систему
 *     tags: [Authentication]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - username
 *               - password
 *             properties:
 *               username:
 *                 type: string
 *               password:
 *                 type: string
 *     responses:
 *       200:
 *         description: Успешный вход
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 user:
 *                   $ref: '#/components/schemas/User'
 *                 token:
 *                   type: string
 *       401:
 *         description: Неверные учетные данные
 */
router.post('/login', authLimiter, validate(loginSchema), asyncHandler(async (req, res) => {
  const { username, password } = req.validated;
  const normalizedUsername = username.trim().toLowerCase();
  
  // Ищем пользователя
  const user = db.prepare(
    'SELECT id, username, display_name, email, password_hash FROM users WHERE username = ?'
  ).get(normalizedUsername);
  
  // Проверяем, что пользователь найден и у него есть password_hash
  if (!user) {
    log.warn({ username: normalizedUsername, ip: req.ip }, 'Login attempt with non-existent username');
    return res.status(401).json({ error: 'Неверное имя пользователя или пароль' });
  }
  
  if (!user.password_hash) {
    log.error({ userId: user.id, username: normalizedUsername }, 'User found but password_hash is missing');
    return res.status(500).json({ error: 'Ошибка сервера. Обратитесь к администратору.' });
  }
  
  // Проверяем пароль
  const isPasswordValid = bcrypt.compareSync(password, user.password_hash);
  
  if (!isPasswordValid) {
    log.warn({ userId: user.id, username: normalizedUsername, ip: req.ip }, 'Failed login attempt - invalid password');
    return res.status(401).json({ error: 'Неверное имя пользователя или пароль' });
  }
  
  const token = signToken(user.id, user.username);
  
  // Audit log
  auditLog(AUDIT_EVENTS.LOGIN, user.id, {
    ip: req.ip || req.connection?.remoteAddress,
    userAgent: req.get('user-agent'),
  });
  
  log.info({ userId: user.id, username: normalizedUsername }, 'Successful login');
  
  res.json({
    user: {
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      email: user.email || null,
    },
    token,
  });
}));

// Восстановление пароля: запрос письма со ссылкой
router.post('/forgot-password', passwordResetLimiter, validate(forgotPasswordSchema), asyncHandler(async (req, res) => {
  const { email } = req.validated;
  const user = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (user) {
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // 1 час
    db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(user.id);
    db.prepare(
      'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)'
    ).run(user.id, tokenHash, expiresAt);
    await sendPasswordResetEmail(email, token);
  }
  res.json({ message: 'Если аккаунт с таким email существует, на него отправлена ссылка для сброса пароля.' });
}));

// Сброс пароля по токену из ссылки
router.post('/reset-password', passwordResetLimiter, validate(resetPasswordSchema), asyncHandler(async (req, res) => {
  const { token, newPassword } = req.validated;
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
}));

// Смена пароля (авторизованный пользователь)
router.post('/change-password', authMiddleware, validate(changePasswordSchema), asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.validated;
  const user = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(req.user.userId);
  if (!user || !bcrypt.compareSync(currentPassword, user.password_hash)) {
    return res.status(401).json({ error: 'Неверный текущий пароль' });
  }
  const password_hash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(password_hash, req.user.userId);
  
  // Audit log
  auditLog(AUDIT_EVENTS.PASSWORD_CHANGE, req.user.userId, {
    ip: req.ip || req.connection?.remoteAddress,
    userAgent: req.get('user-agent'),
  });
  
  res.json({ message: 'Пароль изменён' });
}));

export default router;
