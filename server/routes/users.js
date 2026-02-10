import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { randomUUID } from 'crypto';
import { fileURLToPath } from 'url';
import { mkdirSync, existsSync, unlinkSync } from 'fs';
import db from '../db.js';
import { authMiddleware } from '../auth.js';

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
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    if (!['.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(ext)) {
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
  };
  if (user.friends_count !== undefined) j.friends_count = user.friends_count;
  if (j.email === undefined) delete j.email;
  if (j.phone === undefined) delete j.phone;
  return j;
}

router.get('/me', (req, res) => {
  const user = db.prepare(
    'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email, birthday, phone FROM users WHERE id = ?'
  ).get(req.user.userId);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  const count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(req.user.userId);
  user.friends_count = count?.n ?? 0;
  res.json(userToJson(user, getBaseUrl(req), { includeEmail: true, includePhone: true }));
});

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const BIRTHDAY_RE = /^\d{4}-\d{2}-\d{2}$/;

router.patch('/me', (req, res) => {
  const { display_name, username, bio, email, birthday } = req.body;
  const me = req.user.userId;
  const updates = [];
  const params = [];
  if (typeof display_name === 'string') {
    updates.push('display_name = ?');
    params.push(display_name.trim() || null);
  }
  if (typeof username === 'string') {
    const u = username.trim().toLowerCase();
    if (u.length < 3) return res.status(400).json({ error: 'Имя пользователя минимум 3 символа' });
    updates.push('username = ?');
    params.push(u);
  }
  if (typeof bio === 'string') {
    updates.push('bio = ?');
    params.push(bio.trim().slice(0, 256) || null);
  }
  if (req.body.email !== undefined) {
    const em = typeof email === 'string' ? email.trim().toLowerCase() : null;
    if (em && !EMAIL_RE.test(em)) return res.status(400).json({ error: 'Некорректный email' });
    updates.push('email = ?');
    params.push(em || null);
  }
  if (req.body.birthday !== undefined) {
    const bd = typeof birthday === 'string' ? birthday.trim() || null : null;
    if (bd != null && !BIRTHDAY_RE.test(bd)) return res.status(400).json({ error: 'День рождения в формате ГГГГ-ММ-ДД' });
    updates.push('birthday = ?');
    params.push(bd);
  }
  if (req.body.phone !== undefined) {
    const ph = typeof req.body.phone === 'string' ? req.body.phone.replace(/\D/g, '').trim() || null : null;
    if (ph != null && ph.length < 10) return res.status(400).json({ error: 'Некорректный номер телефона' });
    updates.push('phone = ?');
    params.push(ph);
  }
  if (req.body.public_key !== undefined) {
    const pk = typeof req.body.public_key === 'string' ? req.body.public_key.trim() : null;
    updates.push('public_key = ?');
    params.push(pk && pk.length <= 500 ? pk : null);
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

router.post('/me/avatar', avatarUpload.single('avatar'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Файл не выбран' });
  const me = req.user.userId;
  const avatarPath = req.file.filename;
  db.prepare('UPDATE users SET avatar_path = ? WHERE id = ?').run(avatarPath, me);
  const user = db.prepare('SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email, birthday, phone FROM users WHERE id = ?').get(me);
  user.friends_count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(me)?.n ?? 0;
  res.json(userToJson(user, getBaseUrl(req), { includeEmail: true, includePhone: true }));
});

router.delete('/me', (req, res) => {
  const me = req.user.userId;
  try {
    db.prepare('DELETE FROM poll_votes WHERE user_id = ?').run(me);
    const msgIds = db.prepare('SELECT id FROM messages WHERE sender_id = ? OR receiver_id = ?').all(me, me).map(r => r.id);
    if (msgIds.length > 0) {
      const placeholders = msgIds.map(() => '?').join(',');
      const pollIds = db.prepare(`SELECT id FROM polls WHERE message_id IN (${placeholders})`).all(...msgIds).map(r => r.id);
      if (pollIds.length > 0) {
        const pollPlaceholders = pollIds.map(() => '?').join(',');
        db.prepare(`DELETE FROM poll_votes WHERE poll_id IN (${pollPlaceholders})`).run(...pollIds);
        db.prepare(`DELETE FROM polls WHERE id IN (${pollPlaceholders})`).run(...pollIds);
      }
    }
    db.prepare('DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?').run(me, me);
    db.prepare('DELETE FROM contacts WHERE user_id = ? OR contact_id = ?').run(me, me);
    db.prepare('DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?').run(me, me);
    db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(me);
    const row = db.prepare('SELECT avatar_path FROM users WHERE id = ?').get(me);
    if (row?.avatar_path) {
      const fullPath = path.join(avatarsDir, row.avatar_path);
      if (existsSync(fullPath)) {
        try { unlinkSync(fullPath); } catch (_) {}
      }
    }
    db.prepare('DELETE FROM users WHERE id = ?').run(me);
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
router.post('/find-by-phones', (req, res) => {
  const phones = req.body.phones;
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
});

router.get('/search', (req, res) => {
  const q = (req.query.q || '').trim();
  if (q.length < 2) return res.json([]);
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const rows = db.prepare(`
    SELECT id, username, display_name, bio, avatar_path, public_key, birthday FROM users
    WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
    LIMIT 20
  `).all(me, `%${q}%`, `%${q}%`);
  res.json(rows.map(r => userToJson(r, baseUrl)));
});

/** Публичный профиль: только то, что могут видеть все (без email). Количество друзей — только число, не список. */
router.get('/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: 'Некорректный id' });
  const user = db.prepare(
    'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, birthday FROM users WHERE id = ?'
  ).get(id);
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  const count = db.prepare('SELECT COUNT(*) as n FROM contacts WHERE user_id = ?').get(id);
  user.friends_count = count?.n ?? 0;
  res.json(userToJson(user, getBaseUrl(req)));
});

export default router;
