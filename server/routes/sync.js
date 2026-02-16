import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { log } from '../utils/logger.js';

const router = Router();
router.use(authMiddleware);

/**
 * @swagger
 * /sync/status:
 *   get:
 *     summary: Получить статус синхронизации
 *     tags: [Sync]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Статус синхронизации
 */
router.get('/status', asyncHandler(async (req, res) => {
  const userId = req.user.userId;
  
  // Проверяем наличие непрочитанных сообщений
  const unreadCount = db.prepare(`
    SELECT COUNT(*) as cnt 
    FROM messages 
    WHERE receiver_id = ? AND read_at IS NULL
  `).get(userId)?.cnt || 0;
  
  // Проверяем последнее время активности
  const lastActivity = db.prepare(`
    SELECT MAX(created_at) as last_msg_time
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
  `).get(userId, userId);
  
  res.json({
    synced: true,
    unreadCount,
    lastSyncTime: new Date().toISOString(),
    lastActivityTime: lastActivity?.last_msg_time || null,
  });
}));

/**
 * @swagger
 * /sync/messages:
 *   post:
 *     summary: Синхронизация сообщений (для офлайн режима)
 *     tags: [Sync]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               lastSyncTime:
 *                 type: string
 *                 format: date-time
 *               peerIds:
 *                 type: array
 *                 items:
 *                   type: integer
 *     responses:
 *       200:
 *         description: Синхронизированные сообщения
 */
router.post('/messages', asyncHandler(async (req, res) => {
  const userId = req.user.userId;
  const { lastSyncTime, peerIds = [] } = req.body;
  
  if (!lastSyncTime) {
    return res.status(400).json({ error: 'lastSyncTime обязателен' });
  }
  
  const syncDate = new Date(lastSyncTime);
  
  // Личные сообщения
  let query = `
    SELECT id, sender_id, receiver_id, NULL as group_id, content, created_at, read_at, 
           attachment_path, attachment_filename, message_type, attachment_kind,
           attachment_duration_sec, attachment_encrypted
    FROM messages
    WHERE (sender_id = ? OR receiver_id = ?)
      AND created_at > ?
  `;
  
  const params = [userId, userId, syncDate.toISOString()];
  
  if (peerIds.length > 0) {
    const placeholders = peerIds.map(() => '?').join(',');
    query += ` AND (sender_id IN (${placeholders}) OR receiver_id IN (${placeholders}))`;
    params.push(...peerIds, ...peerIds);
  }
  
  query += ' ORDER BY created_at ASC LIMIT 500';
  
  const personalMessages = db.prepare(query).all(...params);
  
  // Групповые сообщения
  const groupMessages = db.prepare(`
    SELECT gm.id, gm.sender_id, NULL as receiver_id, gm.group_id, gm.content, gm.created_at, gm.read_at,
           gm.attachment_path, gm.attachment_filename, gm.message_type, gm.attachment_kind,
           gm.attachment_duration_sec, gm.attachment_encrypted
    FROM group_messages gm
    JOIN group_members gmem ON gmem.group_id = gm.group_id AND gmem.user_id = ?
    WHERE gm.created_at > ?
    ORDER BY gm.created_at ASC
    LIMIT 500
  `).all(userId, syncDate.toISOString());
  
  const messages = [...personalMessages, ...groupMessages].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  ).slice(0, 1000);
  
  // Получаем обновления реакций (личные + групповые)
  const personalMsgIds = personalMessages.map(m => m.id);
  const groupMsgIds = groupMessages.map(m => m.id);
  let reactionUpdates = [];
  if (personalMsgIds.length > 0) {
    const ph = personalMsgIds.map(() => '?').join(',');
    reactionUpdates = db.prepare(`
      SELECT mr.message_id, mr.emoji, mr.user_id
      FROM message_reactions mr
      WHERE mr.message_id IN (${ph})
    `).all(...personalMsgIds);
  }
  if (groupMsgIds.length > 0) {
    const ph = groupMsgIds.map(() => '?').join(',');
    const gr = db.prepare(`
      SELECT gmr.group_message_id as message_id, gmr.emoji, gmr.user_id
      FROM group_message_reactions gmr
      WHERE gmr.group_message_id IN (${ph})
    `).all(...groupMsgIds);
    reactionUpdates = [...reactionUpdates, ...gr];
  }
  
  // Группируем реакции по message_id
  const reactionsByMessage = {};
  reactionUpdates.forEach(r => {
    if (!reactionsByMessage[r.message_id]) {
      reactionsByMessage[r.message_id] = [];
    }
    reactionsByMessage[r.message_id].push({
      emoji: r.emoji,
      userId: r.user_id,
    });
  });
  
  const baseUrl = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  const baseUrlFull = `${baseUrl}://${host}`;
  
  const result = messages.map(m => ({
    id: m.id,
    senderId: m.sender_id,
    receiverId: m.receiver_id,
    groupId: m.group_id ?? null,
    content: m.content,
    createdAt: m.created_at,
    readAt: m.read_at,
    attachmentUrl: m.attachment_path ? `${baseUrlFull}/uploads/${m.attachment_path}` : null,
    attachmentFilename: m.attachment_filename,
    messageType: m.message_type,
    attachmentKind: m.attachment_kind || 'file',
    attachmentDurationSec: m.attachment_duration_sec,
    attachmentEncrypted: !!(m.attachment_encrypted),
    reactions: reactionsByMessage[m.id] || [],
  }));
  
  res.json({
    messages: result,
    syncTime: new Date().toISOString(),
    count: result.length,
  });
}));

export default router;
