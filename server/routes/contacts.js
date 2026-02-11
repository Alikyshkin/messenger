import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { validate, addContactSchema, validateParams, idParamSchema } from '../middleware/validation.js';
import { validatePagination, createPaginationMeta } from '../middleware/pagination.js';
import { get, set, del, CacheKeys } from '../utils/cache.js';
import config from '../config/index.js';

const router = Router();
router.use(authMiddleware);

router.get('/', validatePagination, async (req, res) => {
  const { limit = 50, offset = 0 } = req.pagination;
  const userId = req.user.userId;
  
  const total = db.prepare('SELECT COUNT(*) as cnt FROM contacts WHERE user_id = ?').get(userId)?.cnt || 0;
  
  const rows = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.is_online, u.last_seen
    FROM contacts c
    JOIN users u ON u.id = c.contact_id
    WHERE c.user_id = ?
    ORDER BY u.display_name, u.username
    LIMIT ? OFFSET ?
  `).all(userId, limit, offset);
  
  res.json({
    data: rows.map(r => ({
      id: r.id,
      username: r.username,
      display_name: r.display_name || r.username,
      is_online: !!(r.is_online),
      last_seen: r.last_seen || null,
    })),
    pagination: createPaginationMeta(total, limit, offset),
  });
});

// Отправить заявку в друзья (друг появляется в списке только после одобрения)
router.post('/', validate(addContactSchema), async (req, res) => {
  const { username } = req.validated;
  const contact = db.prepare(
    'SELECT id, username, display_name FROM users WHERE username = ?'
  ).get(username.toLowerCase());
  if (!contact) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }
  if (contact.id === req.user.userId) {
    return res.status(400).json({ error: 'Нельзя добавить самого себя' });
  }
  const me = req.user.userId;
  const existingContact = db.prepare('SELECT 1 FROM contacts WHERE user_id = ? AND contact_id = ?').get(me, contact.id);
  if (existingContact) {
    return res.status(409).json({ error: 'Уже в друзьях' });
  }
  const existingReq = db.prepare(
    "SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'"
  ).get(me, contact.id);
  if (existingReq) {
    return res.status(409).json({ error: 'Заявка уже отправлена' });
  }
  try {
    db.prepare(
      "INSERT INTO friend_requests (from_user_id, to_user_id, status) VALUES (?, ?, 'pending')"
    ).run(me, contact.id);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json({ error: 'Заявка уже отправлена' });
    }
    throw e;
  }
  res.status(201).json({
    id: contact.id,
    username: contact.username,
    display_name: contact.display_name || contact.username,
  });
});

// Исходящие заявки (кому я отправил заявку)
router.get('/requests/outgoing', (req, res) => {
  const rows = db.prepare(`
    SELECT to_user_id as user_id FROM friend_requests
    WHERE from_user_id = ? AND status = 'pending'
  `).all(req.user.userId);
  res.json(rows.map(r => ({ to_user_id: r.user_id })));
});

// Входящие заявки в друзья
router.get('/requests/incoming', (req, res) => {
  const rows = db.prepare(`
    SELECT fr.id, fr.from_user_id, fr.created_at,
           u.username, u.display_name
    FROM friend_requests fr
    JOIN users u ON u.id = fr.from_user_id
    WHERE fr.to_user_id = ? AND fr.status = 'pending'
    ORDER BY fr.created_at DESC
  `).all(req.user.userId);
  res.json(rows.map(r => ({
    id: r.id,
    from_user_id: r.from_user_id,
    username: r.username,
    display_name: r.display_name || r.username,
    created_at: r.created_at,
  })));
});

// Одобрить заявку: добавляем друг друга в contacts
router.post('/requests/:id/accept', validateParams(idParamSchema), (req, res) => {
  const id = req.validatedParams.id;
  const row = db.prepare(
    "SELECT from_user_id, to_user_id FROM friend_requests WHERE id = ? AND to_user_id = ? AND status = 'pending'"
  ).get(id, req.user.userId);
  if (!row) {
    return res.status(404).json({ error: 'Заявка не найдена' });
  }
  db.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").run(id);
  try {
    db.prepare('INSERT INTO contacts (user_id, contact_id) VALUES (?, ?)').run(row.to_user_id, row.from_user_id);
    db.prepare('INSERT INTO contacts (user_id, contact_id) VALUES (?, ?)').run(row.from_user_id, row.to_user_id);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') { /* уже есть */ }
    else throw e;
  }
  res.status(204).send();
});

// Отклонить заявку
router.post('/requests/:id/reject', validateParams(idParamSchema), (req, res) => {
  const id = req.validatedParams.id;
  const result = db.prepare(
    "UPDATE friend_requests SET status = 'rejected' WHERE id = ? AND to_user_id = ? AND status = 'pending'"
  ).run(id, req.user.userId);
  if (result.changes === 0) {
    return res.status(404).json({ error: 'Заявка не найдена' });
  }
  res.status(204).send();
});

router.delete('/:id', validateParams(idParamSchema), (req, res) => {
  const contactId = req.validatedParams.id;
  const result = db.prepare(
    'DELETE FROM contacts WHERE user_id = ? AND contact_id = ?'
  ).run(req.user.userId, contactId);
  if (result.changes === 0) {
    return res.status(404).json({ error: 'Контакт не найден' });
  }
  res.status(204).send();
});

export default router;
