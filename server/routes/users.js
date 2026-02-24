import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { randomUUID } from 'crypto';
import { fileURLToPath } from 'url';
import { mkdirSync, existsSync, unlinkSync } from 'fs';
import fs from 'fs';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { isBlockedByMe } from '../utils/blocked.js';
import { canSeeStatus } from '../utils/privacy.js';
import { validate, updateUserSchema, updatePrivacySchema, addHideFromSchema, validateParams, idParamSchema } from '../middleware/validation.js';
import { validateFile } from '../middleware/fileValidation.js';
import { FILE_LIMITS, ALLOWED_FILE_TYPES, SEARCH_CONFIG } from '../config/constants.js';
import { get, set, del, CacheKeys } from '../utils/cache.js';
import { deleteUserCascade } from '../utils/userDeletion.js';
import config from '../config/index.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import Joi from 'joi';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const avatarsDir = path.join(__dirname, '../uploads/avatars');
if (!existsSync(avatarsDir)) mkdirSync(avatarsDir, { recursive: true });

const avatarUpload = multer({
  storage: multer.diskStorage({
    destination: avatarsDir,
    filename: (req, file, cb) => {
      const ext = (path.extname(file.originalname) || '').toLowerCase();
      const safe = /^\.(jpg|jpeg|png|gif|webp)$/.test(ext) ? ext : '.jpg';
      cb(null, randomUUID() + safe);
    },
  }),
  limits: { fileSize: FILE_LIMITS.MAX_AVATAR_SIZE },
  fileFilter: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    if (!ALLOWED_FILE_TYPES.IMAGES.includes(ext)) {
      return cb(new Error('Только изображения (jpg, png, gif, webp)'));
    }
    cb(null, true);
  },
});

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

function userToJson(user, baseUrl, options = {}) {
  const j = {
    id: user.id,
    username: user.username,
    display_name: user.display_name || user.username,
    bio: user.bio ?? null,
    avatar_url: user.avatar_path ? `${baseUrl}/uploads/avatars/${user.avatar_path}` : null,
    created_at: user.created_at,
    public_key: user.public_key ?? null,
    email: options.includeEmail ? (user.email ?? null) : undefined,
    birthday: user.birthday ?? null,
    phone: options.includePhone ? (user.phone ?? null) : undefined,
    is_online: user.is_online !== undefined ? !!(user.is_online) : undefined,
    last_seen: user.last_seen || null,
  };
  if (user.friends_count !== undefined) j.friends_count = user.friends_count;
  if (j.email === undefined) delete j.email;
  if (j.phone === undefined) delete j.phone;
  if (j.is_online === undefined) delete j.is_online;
  return j;
}

/**
 * @swagger
 * /users/me:
 *   get:
 *     summary: Получить информацию о текущем пользователе
 *     tags: [Users]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Информация о пользователе
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/User'
 */
router.get('/me', async (req, res) => {
  const userId = req.user.userId;
  
  // Пытаемся получить из кэша
  const cacheKey = CacheKeys.user(userId);
  const cached = await get(cacheKey);
  if (cached) {
    return res.json(cached);
  }
  
  const user = db.prepare(
    'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email, birthday, phone, is_online, last_seen FROM users WHERE id = ?'
  ).get(req.user.userId);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  const count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(req.user.userId);
  user.friends_count = count?.n ?? 0;
  const json = userToJson(user, getBaseUrl(req), { includeEmail: true, includePhone: true });
  json.is_online = !!(user.is_online);
  json.last_seen = user.last_seen || null;
  res.json(json);
});

router.get('/me/privacy', (req, res) => {
  const me = req.user.userId;
  const row = db.prepare('SELECT who_can_see_status, who_can_message, who_can_call FROM user_privacy WHERE user_id = ?').get(me);
  res.json({
    who_can_see_status: row?.who_can_see_status ?? 'contacts',
    who_can_message: row?.who_can_message ?? 'contacts',
    who_can_call: row?.who_can_call ?? 'contacts',
  });
});

router.patch('/me/privacy', validate(updatePrivacySchema), (req, res) => {
  const me = req.user.userId;
  const data = req.validated;
  let who_can_see_status = 'contacts';
  let who_can_message = 'contacts';
  let who_can_call = 'contacts';
  const existing = db.prepare('SELECT who_can_see_status, who_can_message, who_can_call FROM user_privacy WHERE user_id = ?').get(me);
  if (existing) {
    who_can_see_status = existing.who_can_see_status;
    who_can_message = existing.who_can_message;
    who_can_call = existing.who_can_call;
  }
  if (data.who_can_see_status !== undefined) who_can_see_status = data.who_can_see_status;
  if (data.who_can_message !== undefined) who_can_message = data.who_can_message;
  if (data.who_can_call !== undefined) who_can_call = data.who_can_call;
  db.prepare(`
    INSERT INTO user_privacy (user_id, who_can_see_status, who_can_message, who_can_call)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET who_can_see_status = excluded.who_can_see_status, who_can_message = excluded.who_can_message, who_can_call = excluded.who_can_call
  `).run(me, who_can_see_status, who_can_message, who_can_call);
  res.json({ who_can_see_status, who_can_message, who_can_call });
});

router.get('/me/privacy/hide-from', (req, res) => {
  const me = req.user.userId;
  const rows = db.prepare('SELECT hidden_from_user_id FROM user_privacy_hide_from WHERE user_id = ?').all(me);
  res.json({ user_ids: rows.map(r => r.hidden_from_user_id) });
});

router.post('/me/privacy/hide-from', validate(addHideFromSchema), (req, res) => {
  const me = req.user.userId;
  const targetId = req.validated.user_id;
  if (targetId === me) return res.status(400).json({ error: 'Нельзя скрыть статус от себя' });
  try {
    db.prepare('INSERT OR IGNORE INTO user_privacy_hide_from (user_id, hidden_from_user_id) VALUES (?, ?)').run(me, targetId);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT') return res.status(400).json({ error: 'Пользователь не найден' });
    throw e;
  }
  res.status(201).json({ user_id: targetId });
});

router.delete('/me/privacy/hide-from/:id', validateParams(idParamSchema), (req, res) => {
  const me = req.user.userId;
  const targetId = req.validatedParams.id;
  db.prepare('DELETE FROM user_privacy_hide_from WHERE user_id = ? AND hidden_from_user_id = ?').run(me, targetId);
  res.status(204).send();
});

router.patch('/me', validate(updateUserSchema), (req, res) => {
  const data = req.validated;
  const me = req.user.userId;
  const updates = [];
  const params = [];
  if (data.display_name !== undefined) {
    updates.push('display_name = ?');
    params.push(data.display_name || null);
  }
  if (data.username !== undefined) {
    updates.push('username = ?');
    params.push(data.username.toLowerCase());
  }
  if (data.bio !== undefined) {
    updates.push('bio = ?');
    params.push(data.bio || null);
  }
  if (data.email !== undefined) {
    updates.push('email = ?');
    params.push(data.email || null);
  }
  if (data.birthday !== undefined) {
    updates.push('birthday = ?');
    params.push(data.birthday || null);
  }
  if (data.phone !== undefined) {
    updates.push('phone = ?');
    params.push(data.phone || null);
  }
  if (data.public_key !== undefined) {
    updates.push('public_key = ?');
    params.push(data.public_key || null);
  }
  const sel = 'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email, birthday, phone FROM users WHERE id = ?';
  if (updates.length === 0) {
    const user = db.prepare(sel).get(me);
    user.friends_count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(me)?.n ?? 0;
    return res.json(userToJson(user, getBaseUrl(req), { includeEmail: true }));
  }
  params.push(me);
  try {
    db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...params);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') return res.status(409).json({ error: 'Это имя пользователя уже занято' });
    throw e;
  }
  const user = db.prepare(sel).get(me);
  user.friends_count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(me)?.n ?? 0;
  res.json(userToJson(user, getBaseUrl(req), { includeEmail: true, includePhone: true }));
});

router.post('/me/avatar', avatarUpload.single('avatar'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Файл не выбран' });
  const me = req.user.userId;
  const avatarPath = req.file.filename;
  const fullPath = path.join(avatarsDir, avatarPath);
  
  // Проверка файла аватара на безопасность
    const fileValidation = await validateFile(fullPath, FILE_LIMITS.MAX_AVATAR_SIZE);
  if (!fileValidation.valid) {
    // Удаляем небезопасный файл
    try { fs.unlinkSync(fullPath); } catch (_) {}
    return res.status(400).json({ error: fileValidation.error || 'Файл не прошёл проверку безопасности' });
  }
  
  // Проверяем, что это изображение
  if (!fileValidation.mime || !fileValidation.mime.startsWith('image/')) {
    try { fs.unlinkSync(fullPath); } catch (_) {}
    return res.status(400).json({ error: 'Аватар должен быть изображением' });
  }
  
  db.prepare('UPDATE users SET avatar_path = ? WHERE id = ?').run(avatarPath, me);
  const user = db.prepare('SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email, birthday, phone FROM users WHERE id = ?').get(me);
  user.friends_count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(me)?.n ?? 0;
  res.json(userToJson(user, getBaseUrl(req), { includeEmail: true, includePhone: true }));
});

router.delete('/me', (req, res) => {
  const me = req.user.userId;
  try {
    deleteUserCascade(db, me, { avatarsDir });
  } catch (e) {
    return res.status(500).json({ error: 'Не удалось удалить аккаунт' });
  }
  res.status(204).send();
});

/** Нормализация номера телефона: только цифры (для поиска и хранения). */
function normalizePhone(s) {
  if (typeof s !== 'string') return '';
  return s.replace(/\D/g, '');
}

/** Найти пользователей по списку номеров телефонов (из контактов устройства). */
const findUsersByPhonesSchema = Joi.object({
  phones: Joi.array().items(Joi.string().min(10).max(15)).min(1).max(1000).required()
    .label('Номера телефонов')
    .messages({
      'any.required': 'Список номеров телефонов обязателен',
      'array.base': 'Номера телефонов должны быть списком',
      'array.min': 'Список номеров телефонов не может быть пустым',
      'array.max': 'Слишком много номеров телефонов (максимум 1000)',
    }),
});

router.post('/find-by-phones', validate(findUsersByPhonesSchema), asyncHandler(async (req, res) => {
  const phones = req.validated.phones;
  if (!Array.isArray(phones) || phones.length === 0) return res.json([]);
  const normalizedSet = new Set(phones.map(normalizePhone).filter(p => p.length >= 10));
  if (normalizedSet.size === 0) return res.json([]);
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const allWithPhone = db.prepare(`
    SELECT id, username, display_name, bio, avatar_path, public_key, birthday, phone
    FROM users
    WHERE id != ? AND phone IS NOT NULL AND TRIM(phone) != ''
  `).all(me);
  const matched = allWithPhone.filter(u => normalizedSet.has(normalizePhone(u.phone || '')));
  res.json(matched.map(r => userToJson(r, baseUrl)));
}));

/** Список заблокированных пользователей */
router.get('/blocked', (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const rows = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_online, u.last_seen
    FROM blocked_users b
    JOIN users u ON u.id = b.blocked_id
    WHERE b.blocker_id = ?
    ORDER BY b.created_at DESC
  `).all(me);
  res.json(rows.map(r => ({
    ...userToJson(r, baseUrl),
    is_online: !!(r.is_online),
    last_seen: r.last_seen || null,
  })));
});

/** Заблокировать пользователя */
router.post('/:id/block', validateParams(idParamSchema), (req, res) => {
  const blockedId = req.validatedParams.id;
  const me = req.user.userId;
  if (blockedId === me) return res.status(400).json({ error: 'Нельзя заблокировать самого себя' });
  const user = db.prepare('SELECT id FROM users WHERE id = ?').get(blockedId);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  try {
    db.prepare('INSERT INTO blocked_users (blocker_id, blocked_id) VALUES (?, ?)').run(me, blockedId);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_PRIMARYKEY') {
      return res.status(409).json({ error: 'Пользователь уже заблокирован' });
    }
    throw e;
  }
  res.status(204).send();
});

/** Разблокировать пользователя */
router.delete('/:id/block', validateParams(idParamSchema), (req, res) => {
  const blockedId = req.validatedParams.id;
  const me = req.user.userId;
  const result = db.prepare('DELETE FROM blocked_users WHERE blocker_id = ? AND blocked_id = ?').run(me, blockedId);
  if (result.changes === 0) return res.status(404).json({ error: 'Пользователь не был заблокирован' });
  res.status(204).send();
});

router.get('/search', (req, res) => {
  const q = (req.query.q || '').trim();
  if (q.length < SEARCH_CONFIG.MIN_QUERY_LENGTH) return res.json([]);
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const rows = db.prepare(`
    SELECT id, username, display_name, bio, avatar_path, public_key, birthday FROM users
    WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
    LIMIT ?
  `).all(me, `%${q}%`, `%${q}%`, SEARCH_CONFIG.MAX_RESULTS);
  res.json(rows.map(r => userToJson(r, baseUrl)));
});

/** Публичный профиль: только то, что могут видеть все (без email). Количество друзей — только число, не список. */
router.get('/:id', validateParams(idParamSchema), (req, res) => {
  const id = req.validatedParams.id;
  const me = req.user.userId;
  const user = db.prepare(
    'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, birthday, is_online, last_seen FROM users WHERE id = ?'
  ).get(id);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  const count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(id);
  user.friends_count = count?.n ?? 0;
  const json = userToJson(user, getBaseUrl(req));
  if (me === id || canSeeStatus(me, id)) {
    json.is_online = !!(user.is_online);
    json.last_seen = user.last_seen || null;
  } else {
    json.is_online = null;
    json.last_seen = null;
  }
  if (me !== id) {
    json.is_blocked = isBlockedByMe(me, id);
  }
  res.json(json);
});

export default router;
