import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { validatePagination, createPaginationMeta } from '../middleware/pagination.js';
import { validateParams, peerIdParamSchema } from '../middleware/validation.js';
import { ALLOWED_FILE_TYPES } from '../config/constants.js';

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

/**
 * @swagger
 * /media/{peerId}:
 *   get:
 *     summary: Получить медиа файлы (фото/видео) из чата
 *     tags: [Media]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: peerId
 *         required: true
 *         schema:
 *           type: integer
 *       - in: query
 *         name: type
 *         schema:
 *           type: string
 *           enum: [all, photo, video]
 *           default: all
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
 *         description: Список медиа файлов
 */
router.get('/:peerId', validateParams(peerIdParamSchema), validatePagination, (req, res) => {
  const peerId = req.validatedParams.peerId;
  const me = req.user.userId;
  const { limit = 50, offset = 0 } = req.pagination;
  const type = req.query.type || 'all'; // 'all', 'photo', 'video'
  const baseUrl = getBaseUrl(req);

  // Проверяем доступ к чату
  const chatExists = db.prepare(`
    SELECT 1 FROM messages 
    WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
    LIMIT 1
  `).get(me, peerId, peerId, me);

  if (!chatExists) {
    return res.status(404).json({ error: 'Чат не найден' });
  }

  // Определяем фильтр по типу медиа
  let typeFilter = '';
  if (type === 'photo') {
    typeFilter = `AND (m.attachment_kind = 'file' OR m.attachment_kind IS NULL) 
                  AND m.attachment_filename IS NOT NULL
                  AND (LOWER(m.attachment_filename) LIKE '%.jpg' 
                    OR LOWER(m.attachment_filename) LIKE '%.jpeg' 
                    OR LOWER(m.attachment_filename) LIKE '%.png' 
                    OR LOWER(m.attachment_filename) LIKE '%.gif' 
                    OR LOWER(m.attachment_filename) LIKE '%.webp')`;
  } else if (type === 'video') {
    typeFilter = `AND (m.attachment_kind = 'file' OR m.attachment_kind = 'video_note')
                  AND m.attachment_filename IS NOT NULL
                  AND (LOWER(m.attachment_filename) LIKE '%.mp4' 
                    OR LOWER(m.attachment_filename) LIKE '%.webm' 
                    OR LOWER(m.attachment_filename) LIKE '%.mov'
                    OR m.attachment_kind = 'video_note')`;
  }

  // Получаем медиа файлы
  const media = db.prepare(`
    SELECT 
      m.id,
      m.sender_id,
      m.receiver_id,
      m.attachment_path,
      m.attachment_filename,
      m.attachment_kind,
      m.attachment_duration_sec,
      m.created_at,
      m.attachment_encrypted,
      u.display_name as sender_display_name,
      u.username as sender_username
    FROM messages m
    LEFT JOIN users u ON u.id = m.sender_id
    WHERE ((m.sender_id = ? AND m.receiver_id = ?) OR (m.sender_id = ? AND m.receiver_id = ?))
      AND m.attachment_path IS NOT NULL
      ${typeFilter}
    ORDER BY m.created_at DESC
    LIMIT ? OFFSET ?
  `).all(me, peerId, peerId, me, limit, offset);

  // Подсчитываем общее количество
  const total = db.prepare(`
    SELECT COUNT(*) as cnt
    FROM messages m
    WHERE ((m.sender_id = ? AND m.receiver_id = ?) OR (m.sender_id = ? AND m.receiver_id = ?))
      AND m.attachment_path IS NOT NULL
      ${typeFilter}
  `).get(me, peerId, peerId, me)?.cnt || 0;

  const results = media.map(m => {
    const isPhoto = m.attachment_kind === 'file' && m.attachment_filename && 
      ALLOWED_FILE_TYPES.IMAGES.some(ext => 
        m.attachment_filename.toLowerCase().endsWith(ext.toLowerCase())
      );
    const isVideo = m.attachment_kind === 'video_note' || 
      (m.attachment_kind === 'file' && m.attachment_filename && 
       ALLOWED_FILE_TYPES.VIDEOS.some(ext => 
         m.attachment_filename.toLowerCase().endsWith(ext.toLowerCase())
       ));

    return {
      id: m.id,
      messageId: m.id,
      senderId: m.sender_id,
      senderDisplayName: m.sender_display_name || m.sender_username,
      url: `${baseUrl}/uploads/${m.attachment_path}`,
      thumbnailUrl: isPhoto ? `${baseUrl}/uploads/${m.attachment_path}` : null,
      filename: m.attachment_filename,
      type: isVideo ? 'video' : isPhoto ? 'photo' : 'file',
      durationSec: m.attachment_duration_sec,
      createdAt: m.created_at,
      encrypted: !!(m.attachment_encrypted),
    };
  });

  res.json({
    data: results,
    pagination: createPaginationMeta(total, limit, offset),
  });
});

/**
 * @swagger
 * /media/groups/{groupId}:
 *   get:
 *     summary: Получить медиа файлы из группового чата
 *     tags: [Media]
 *     security:
 *       - bearerAuth: []
 */
router.get('/groups/:groupId', validatePagination, (req, res) => {
  const groupId = parseInt(req.params.groupId, 10);
  const me = req.user.userId;
  const { limit = 50, offset = 0 } = req.pagination;
  const type = req.query.type || 'all';
  const baseUrl = getBaseUrl(req);

  // Проверяем доступ к группе
  const member = db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, me);
  if (!member) {
    return res.status(403).json({ error: 'Нет доступа к группе' });
  }

  let typeFilter = '';
  if (type === 'photo') {
    typeFilter = `AND (gm.attachment_kind = 'file' OR gm.attachment_kind IS NULL) 
                  AND gm.attachment_filename IS NOT NULL
                  AND (LOWER(gm.attachment_filename) LIKE '%.jpg' 
                    OR LOWER(gm.attachment_filename) LIKE '%.jpeg' 
                    OR LOWER(gm.attachment_filename) LIKE '%.png' 
                    OR LOWER(gm.attachment_filename) LIKE '%.gif' 
                    OR LOWER(gm.attachment_filename) LIKE '%.webp')`;
  } else if (type === 'video') {
    typeFilter = `AND (gm.attachment_kind = 'file' OR gm.attachment_kind = 'video_note')
                  AND gm.attachment_filename IS NOT NULL
                  AND (LOWER(gm.attachment_filename) LIKE '%.mp4' 
                    OR LOWER(gm.attachment_filename) LIKE '%.webm' 
                    OR LOWER(gm.attachment_filename) LIKE '%.mov'
                    OR gm.attachment_kind = 'video_note')`;
  }

  const media = db.prepare(`
    SELECT 
      gm.id,
      gm.group_id,
      gm.sender_id,
      gm.attachment_path,
      gm.attachment_filename,
      gm.attachment_kind,
      gm.attachment_duration_sec,
      gm.created_at,
      gm.attachment_encrypted,
      u.display_name as sender_display_name,
      u.username as sender_username
    FROM group_messages gm
    LEFT JOIN users u ON u.id = gm.sender_id
    WHERE gm.group_id = ?
      AND gm.attachment_path IS NOT NULL
      ${typeFilter}
    ORDER BY gm.created_at DESC
    LIMIT ? OFFSET ?
  `).all(groupId, limit, offset);

  const total = db.prepare(`
    SELECT COUNT(*) as cnt
    FROM group_messages gm
    WHERE gm.group_id = ?
      AND gm.attachment_path IS NOT NULL
      ${typeFilter}
  `).get(groupId)?.cnt || 0;

  const results = media.map(m => {
    const isPhoto = m.attachment_kind === 'file' && m.attachment_filename && 
      ALLOWED_FILE_TYPES.IMAGES.some(ext => 
        m.attachment_filename.toLowerCase().endsWith(ext.toLowerCase())
      );
    const isVideo = m.attachment_kind === 'video_note' || 
      (m.attachment_kind === 'file' && m.attachment_filename && 
       ALLOWED_FILE_TYPES.VIDEOS.some(ext => 
         m.attachment_filename.toLowerCase().endsWith(ext.toLowerCase())
       ));

    return {
      id: m.id,
      messageId: m.id,
      groupId: m.group_id,
      senderId: m.sender_id,
      senderDisplayName: m.sender_display_name || m.sender_username,
      url: `${baseUrl}/uploads/${m.attachment_path}`,
      thumbnailUrl: isPhoto ? `${baseUrl}/uploads/${m.attachment_path}` : null,
      filename: m.attachment_filename,
      type: isVideo ? 'video' : isPhoto ? 'photo' : 'file',
      durationSec: m.attachment_duration_sec,
      createdAt: m.created_at,
      encrypted: !!(m.attachment_encrypted),
    };
  });

  res.json({
    data: results,
    pagination: createPaginationMeta(total, limit, offset),
  });
});

export default router;
