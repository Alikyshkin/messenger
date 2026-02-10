import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { decryptIfLegacy } from '../cipher.js';

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

router.get('/', (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const lastIds = db.prepare(`
    SELECT MAX(id) as mid, 
      CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS peer_id
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
    GROUP BY peer_id
  `).all(me, me, me);
  const result = lastIds.map(({ mid, peer_id }) => {
    const msg = db.prepare('SELECT id, content, created_at, sender_id, message_type FROM messages WHERE id = ?').get(mid);
    const user = db.prepare('SELECT id, username, display_name, bio, avatar_path, public_key FROM users WHERE id = ?').get(peer_id);
    return {
      peer: {
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        bio: user.bio ?? null,
        avatar_url: user.avatar_path ? `${baseUrl}/uploads/avatars/${user.avatar_path}` : null,
        public_key: user.public_key ?? null,
      },
      last_message: {
        id: msg.id,
        content: decryptIfLegacy(msg.content),
        created_at: msg.created_at,
        is_mine: msg.sender_id === me,
        message_type: msg.message_type || 'text',
      },
    };
  });
  result.sort((a, b) => new Date(b.last_message.created_at) - new Date(a.last_message.created_at));
  res.json(result);
});

export default router;
