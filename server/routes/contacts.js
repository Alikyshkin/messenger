import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';

const router = Router();
router.use(authMiddleware);

router.get('/', (req, res) => {
  const rows = db.prepare(`
    SELECT u.id, u.username, u.display_name
    FROM contacts c
    JOIN users u ON u.id = c.contact_id
    WHERE c.user_id = ?
    ORDER BY u.display_name, u.username
  `).all(req.user.userId);
  res.json(rows.map(r => ({
    id: r.id,
    username: r.username,
    display_name: r.display_name || r.username,
  })));
});

router.post('/', (req, res) => {
  const { username } = req.body;
  if (!username?.trim()) {
    return res.status(400).json({ error: 'Username required' });
  }
  const contact = db.prepare(
    'SELECT id, username, display_name FROM users WHERE username = ?'
  ).get(username.trim().toLowerCase());
  if (!contact) {
    return res.status(404).json({ error: 'User not found' });
  }
  if (contact.id === req.user.userId) {
    return res.status(400).json({ error: 'Cannot add yourself' });
  }
  try {
    db.prepare('INSERT INTO contacts (user_id, contact_id) VALUES (?, ?)')
      .run(req.user.userId, contact.id);
  } catch (e) {
    if (e.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json({ error: 'Already in contacts' });
    }
    throw e;
  }
  res.status(201).json({
    id: contact.id,
    username: contact.username,
    display_name: contact.display_name || contact.username,
  });
});

router.delete('/:id', (req, res) => {
  const contactId = parseInt(req.params.id, 10);
  if (Number.isNaN(contactId)) {
    return res.status(400).json({ error: 'Invalid id' });
  }
  const result = db.prepare(
    'DELETE FROM contacts WHERE user_id = ? AND contact_id = ?'
  ).run(req.user.userId, contactId);
  if (result.changes === 0) {
    return res.status(404).json({ error: 'Contact not found' });
  }
  res.status(204).send();
});

export default router;
