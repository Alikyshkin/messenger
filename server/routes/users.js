import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { randomUUID } from 'crypto';
import { fileURLToPath } from 'url';
import { mkdirSync, existsSync } from 'fs';
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

function userToJson(user, baseUrl) {
  return {
    id: user.id,
    username: user.username,
    display_name: user.display_name || user.username,
    bio: user.bio || null,
    avatar_url: user.avatar_path ? `${baseUrl}/uploads/avatars/${user.avatar_path}` : null,
    created_at: user.created_at,
    public_key: user.public_key || null,
    email: user.email || null,
  };
}

router.get('/me', (req, res) => {
  const user = db.prepare(
    'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email FROM users WHERE id = ?'
  ).get(req.user.userId);
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json(userToJson(user, getBaseUrl(req)));
});

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.patch('/me', (req, res) => {
  const { display_name, username, bio, email } = req.body;
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
  if (req.body.public_key !== undefined) {
    const pk = typeof req.body.public_key === 'string' ? req.body.public_key.trim() : null;
    updates.push('public_key = ?');
    params.push(pk && pk.length <= 500 ? pk : null);
  }
  const sel = 'SELECT id, username, display_name, bio, avatar_path, created_at, public_key, email FROM users WHERE id = ?';
  if (updates.length === 0) {
    const user = db.prepare(sel).get(me);
    return res.json(userToJson(user, getBaseUrl(req)));
  }
  params.push(me);
  try {
    db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...params);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') return res.status(409).json({ error: 'Это имя пользователя уже занято' });
    throw e;
  }
  const user = db.prepare(sel).get(me);
  res.json(userToJson(user, getBaseUrl(req)));
});

router.post('/me/avatar', avatarUpload.single('avatar'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Файл не выбран' });
  const me = req.user.userId;
  const avatarPath = req.file.filename;
  db.prepare('UPDATE users SET avatar_path = ? WHERE id = ?').run(avatarPath, me);
  const user = db.prepare('SELECT id, username, display_name, bio, avatar_path, created_at, public_key FROM users WHERE id = ?').get(me);
  res.json(userToJson(user, getBaseUrl(req)));
});

router.get('/search', (req, res) => {
  const q = (req.query.q || '').trim();
  if (q.length < 2) return res.json([]);
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const rows = db.prepare(`
    SELECT id, username, display_name, bio, avatar_path, public_key FROM users
    WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
    LIMIT 20
  `).all(me, `%${q}%`, `%${q}%`);
  res.json(rows.map(r => userToJson(r, baseUrl)));
});

export default router;
