import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { decryptIfLegacy } from '../cipher.js';
import { validatePagination, createPaginationMeta } from '../middleware/pagination.js';

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

/**
 * @swagger
 * /chats:
 *   get:
 *     summary: Получить список чатов
 *     tags: [Chats]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 50
 *       - in: query
 *         name: offset
 *         schema:
 *           type: integer
 *           default: 0
 *     responses:
 *       200:
 *         description: Список чатов
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 data:
 *                   type: array
 *                   items:
 *                     type: object
 *                 pagination:
 *                   type: object
 */
router.get('/', validatePagination, (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const { limit = 50, offset = 0 } = req.pagination;
  
  // 1-1 чаты
  const lastIds = db.prepare(`
    SELECT MAX(id) as mid, 
      CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS peer_id
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
    GROUP BY peer_id
    ORDER BY mid DESC
    LIMIT ? OFFSET ?
  `).all(me, me, me, limit, offset);
  
  const totalChats = db.prepare(`
    SELECT COUNT(DISTINCT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END) as cnt
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
  `).get(me, me, me)?.cnt || 0;
  const unreadCounts = db.prepare(`
    SELECT sender_id AS peer_id, COUNT(*) AS cnt
    FROM messages
    WHERE receiver_id = ? AND read_at IS NULL
    GROUP BY sender_id
  `).all(me);
  const unreadMap = Object.fromEntries(unreadCounts.map((r) => [r.peer_id, r.cnt]));
  const result = lastIds.map(({ mid, peer_id }) => {
    const msg = db.prepare('SELECT id, content, created_at, sender_id, message_type FROM messages WHERE id = ?').get(mid);
    const user = db.prepare('SELECT id, username, display_name, bio, avatar_path, public_key, is_online, last_seen FROM users WHERE id = ?').get(peer_id);
    const isOnline = !!(user.is_online);
    return {
      peer: {
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        bio: user.bio ?? null,
        avatar_url: user.avatar_path ? `${baseUrl}/uploads/avatars/${user.avatar_path}` : null,
        public_key: user.public_key ?? null,
        is_online: isOnline,
        last_seen: user.last_seen || null,
      },
      group: null,
      last_message: {
        id: msg.id,
        content: decryptIfLegacy(msg.content),
        created_at: msg.created_at,
        is_mine: msg.sender_id === me,
        message_type: msg.message_type || 'text',
      },
      unread_count: unreadMap[peer_id] ?? 0,
    };
  });

  // Групповые чаты
  const myGroups = db.prepare('SELECT group_id FROM group_members WHERE user_id = ?').all(me);
  for (const { group_id } of myGroups) {
    const lastRow = db.prepare('SELECT id, sender_id, content, created_at, message_type FROM group_messages WHERE group_id = ? ORDER BY id DESC LIMIT 1').get(group_id);
    if (!lastRow) continue;
    const group = db.prepare('SELECT id, name, avatar_path, created_by_user_id, created_at FROM groups WHERE id = ?').get(group_id);
    const readRow = db.prepare('SELECT last_read_message_id FROM group_read WHERE group_id = ? AND user_id = ?').get(group_id, me);
    const lastRead = readRow?.last_read_message_id ?? 0;
    const unreadCnt = db.prepare('SELECT COUNT(*) AS c FROM group_messages WHERE group_id = ? AND id > ?').get(group_id, lastRead)?.c ?? 0;
    const sender = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(lastRow.sender_id);
    result.push({
      peer: null,
      group: {
        id: group.id,
        name: group.name,
        avatar_url: group.avatar_path ? `${baseUrl}/uploads/group_avatars/${group.avatar_path}` : null,
        created_by_user_id: group.created_by_user_id,
        created_at: group.created_at,
      },
      last_message: {
        id: lastRow.id,
        content: decryptIfLegacy(lastRow.content),
        created_at: lastRow.created_at,
        is_mine: lastRow.sender_id === me,
        message_type: lastRow.message_type || 'text',
        sender_display_name: sender?.display_name || sender?.username || '?',
      },
      unread_count: unreadCnt,
    });
  }

  result.sort((a, b) => new Date(b.last_message.created_at) - new Date(a.last_message.created_at));
  
  res.json({
    data: result,
    pagination: createPaginationMeta(totalChats, limit, offset),
  });
});

export default router;
