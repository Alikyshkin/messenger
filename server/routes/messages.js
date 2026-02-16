import { Router } from 'express';
import multer from 'multer';
import { randomUUID } from 'crypto';
import path from 'path';
import fs from 'fs';
import zlib from 'zlib';
import { fileURLToPath } from 'url';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { notifyNewMessage, notifyReaction, notifyMessageEdited } from '../realtime.js';
import { decryptIfLegacy } from '../cipher.js';
import { messageLimiter, uploadLimiter } from '../middleware/rateLimit.js';
import { sanitizeText } from '../middleware/sanitize.js';
import { validate, sendMessageSchema, validateParams, peerIdParamSchema, messageIdParamSchema, addReactionSchema, editMessageSchema } from '../middleware/validation.js';
import { validateFile } from '../middleware/fileValidation.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { ALLOWED_REACTION_EMOJIS, FILE_LIMITS, ALLOWED_FILE_TYPES } from '../config/constants.js';
import { syncMessagesFTS } from '../utils/ftsSync.js';
import { log } from '../utils/logger.js';
import { isCommunicationBlocked } from '../utils/blocked.js';
import { canMessage } from '../utils/privacy.js';
const ALLOWED_EMOJIS = new Set(ALLOWED_REACTION_EMOJIS);
function getMessageReactions(messageId) {
  const rows = db.prepare('SELECT user_id, emoji FROM message_reactions WHERE message_id = ?').all(messageId);
  const byEmoji = {};
  for (const r of rows) {
    if (!ALLOWED_EMOJIS.has(r.emoji)) continue;
    if (!byEmoji[r.emoji]) byEmoji[r.emoji] = [];
    byEmoji[r.emoji].push(r.user_id);
  }
  return Object.entries(byEmoji).map(([emoji, user_ids]) => ({ emoji, user_ids }));
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const uploadsDir = path.join(__dirname, '../uploads');

const storage = multer.diskStorage({
  destination: uploadsDir,
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '';
    const safe = (ext && /^\.\w+$/.test(ext)) ? ext : '';
    cb(null, randomUUID() + safe);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: FILE_LIMITS.MAX_FILE_SIZE },
  fileFilter: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    if (ALLOWED_FILE_TYPES.BLOCKED.some(b => ext === b)) {
      return cb(new Error('Тип файла не разрешён'));
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

router.patch('/:peerId/read', validateParams(peerIdParamSchema), asyncHandler(async (req, res) => {
  const peerId = Number(req.validatedParams.peerId);
  const me = Number(req.user.userId);
  log.route('messages', 'PATCH /:peerId/read', 'START', { peerId, me });
  try {
    const stmt = db.prepare(
      'UPDATE messages SET read_at = CURRENT_TIMESTAMP WHERE receiver_id = ? AND sender_id = ? AND read_at IS NULL'
    );
    const result = stmt.run(me, peerId);
    log.route('messages', 'PATCH /:peerId/read', 'DB_UPDATE', { peerId, me, changes: result.changes });
  } catch (err) {
    log.route('messages', 'PATCH /:peerId/read', 'ERROR', { peerId, me, code: err.code }, err.message);
    log.error({ err, peerId, me, code: err.code, message: err.message, stack: err.stack }, 'PATCH /messages/:peerId/read - DB error');
    throw err;
  }
  log.route('messages', 'PATCH /:peerId/read', 'END', { peerId, me }, 'ok');
  res.status(204).send();
}));

router.patch('/:messageId', validateParams(messageIdParamSchema), validate(editMessageSchema), asyncHandler(async (req, res) => {
  const messageId = Number(req.validatedParams.messageId);
  const { content } = req.validated;
  const me = Number(req.user.userId);
  const row = db.prepare('SELECT id, sender_id, receiver_id, content, message_type, attachment_path FROM messages WHERE id = ?').get(messageId);
  if (!row) return res.status(404).json({ error: 'Сообщение не найдено' });
  if (Number(row.sender_id) !== me) return res.status(403).json({ error: 'Только отправитель может редактировать сообщение' });
  if (row.message_type !== 'text' || row.attachment_path) {
    return res.status(400).json({ error: 'Редактировать можно только текстовые сообщения без вложений' });
  }
  const sanitized = sanitizeText(content);
  try {
    db.prepare('UPDATE messages SET content = ? WHERE id = ?').run(sanitized, messageId);
    try {
      db.prepare('UPDATE messages_fts SET content = ? WHERE rowid = ?').run(sanitized, messageId);
    } catch (_) {}
    notifyMessageEdited(messageId, Number(row.sender_id), Number(row.receiver_id), sanitized);
    const updated = db.prepare('SELECT id, content, created_at FROM messages WHERE id = ?').get(messageId);
    res.json({
      id: updated.id,
      content: decryptIfLegacy(updated.content),
      created_at: updated.created_at,
    });
  } catch (err) {
    log.error({ err, messageId, me, code: err.code, message: err.message, stack: err.stack }, 'PATCH /messages/:messageId - DB error');
    throw err;
  }
}));

router.post('/:messageId/reaction', validateParams(messageIdParamSchema), validate(addReactionSchema), asyncHandler(async (req, res) => {
  const messageId = req.validatedParams.messageId;
  const { emoji } = req.validated;
  const me = req.user.userId;
  const row = db.prepare('SELECT id, sender_id, receiver_id FROM messages WHERE id = ?').get(messageId);
  if (!row) return res.status(404).json({ error: 'Сообщение не найдено' });
  if (row.sender_id !== me && row.receiver_id !== me) return res.status(403).json({ error: 'Нет доступа' });
  const existing = db.prepare('SELECT emoji FROM message_reactions WHERE message_id = ? AND user_id = ?').get(messageId, me);
  if (existing) {
    if (existing.emoji === emoji) {
      db.prepare('DELETE FROM message_reactions WHERE message_id = ? AND user_id = ?').run(messageId, me);
    } else {
      db.prepare('UPDATE message_reactions SET emoji = ? WHERE message_id = ? AND user_id = ?').run(emoji, messageId, me);
    }
  } else {
    db.prepare('INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (?, ?, ?)').run(messageId, me, emoji);
  }
  const reactions = getMessageReactions(messageId);
  notifyReaction(messageId, row.sender_id, row.receiver_id, reactions);
  res.json({ reactions });
}));

/**
 * @swagger
 * /messages/{peerId}:
 *   get:
 *     summary: Получить сообщения с пользователем
 *     tags: [Messages]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: peerId
 *         required: true
 *         schema:
 *           type: integer
 *         description: ID собеседника
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 100
 *           maximum: 200
 *         description: Количество сообщений
 *       - in: query
 *         name: before
 *         schema:
 *           type: integer
 *         description: ID сообщения для пагинации (получить сообщения до этого ID)
 *     responses:
 *       200:
 *         description: Список сообщений
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 data:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Message'
 *                 pagination:
 *                   type: object
 *                   properties:
 *                     total:
 *                       type: integer
 *                     limit:
 *                       type: integer
 *                     hasMore:
 *                       type: boolean
 */
router.get('/:peerId', validateParams(peerIdParamSchema), asyncHandler(async (req, res) => {
  const peerId = req.validatedParams.peerId;
  const limit = Math.min(parseInt(req.query.limit, 10) || 100, 200);
  const before = req.query.before ? parseInt(req.query.before, 10) : null;
  const me = req.user.userId;
  if (isCommunicationBlocked(me, peerId)) {
    return res.status(403).json({ error: 'Нет доступа к чату' });
  }
  const baseUrl = getBaseUrl(req);

  let query = `
    SELECT m.id, m.sender_id, m.receiver_id, m.content, m.created_at, m.read_at, m.attachment_path, m.attachment_filename, m.message_type, m.poll_id, m.attachment_kind, m.attachment_duration_sec, m.attachment_encrypted, m.reply_to_id, m.is_forwarded, m.forward_from_sender_id, m.forward_from_display_name, m.sender_public_key
    FROM messages m
    LEFT JOIN message_deleted_for mdf ON mdf.message_id = m.id AND mdf.user_id = ?
    WHERE mdf.message_id IS NULL
      AND ((m.sender_id = ? AND m.receiver_id = ?) OR (m.sender_id = ? AND m.receiver_id = ?))
  `;
  const params = [me, me, peerId, peerId, me];
  if (before && !Number.isNaN(before)) {
    query += ' AND m.id < ?';
    params.push(before);
  }
  query += ' ORDER BY m.id DESC LIMIT ?';
  params.push(limit);

  let rows;
  try {
    rows = db.prepare(query).all(...params);
  } catch (e) {
    if (e.message && e.message.includes('message_deleted_for')) {
      rows = db.prepare(`
        SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key
        FROM messages
        WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
        ${before && !Number.isNaN(before) ? 'AND id < ?' : ''}
        ORDER BY id DESC LIMIT ?
      `).all(me, peerId, peerId, me, ...(before && !Number.isNaN(before) ? [before] : []), limit);
    } else {
      throw e;
    }
  }
  const list = rows.reverse().map(r => {
    const senderKey = r.sender_public_key ?? db.prepare('SELECT public_key FROM users WHERE id = ?').get(r.sender_id)?.public_key;
    const msg = {
      id: r.id,
      sender_id: r.sender_id,
      receiver_id: r.receiver_id,
      content: decryptIfLegacy(r.content),
      created_at: r.created_at,
      read_at: r.read_at,
      is_mine: r.sender_id === me,
      attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
      attachment_filename: r.attachment_filename || null,
      message_type: r.message_type || 'text',
      poll_id: r.poll_id ?? null,
      attachment_kind: r.attachment_kind || 'file',
      attachment_duration_sec: r.attachment_duration_sec ?? null,
      attachment_encrypted: !!(r.attachment_encrypted),
      sender_public_key: senderKey ?? null,
      reply_to_id: r.reply_to_id ?? null,
      is_forwarded: !!(r.is_forwarded),
      forward_from_sender_id: r.forward_from_sender_id ?? null,
      forward_from_display_name: r.forward_from_display_name ?? null,
    };
    if (r.reply_to_id) {
      const replyRow = db.prepare('SELECT content, sender_id FROM messages WHERE id = ?').get(r.reply_to_id);
      if (replyRow) {
        const replySender = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(replyRow.sender_id);
        const replyName = replySender?.display_name || replySender?.username || '?';
        let snippet = replyRow.content || '';
        if (snippet.length > 80) snippet = snippet.slice(0, 77) + '...';
        msg.reply_to_content = snippet;
        msg.reply_to_sender_name = replyName;
      }
    }
    if (r.poll_id) {
      const pollRow = db.prepare('SELECT id, question, options, multiple FROM polls WHERE id = ?').get(r.poll_id);
      if (pollRow) {
        const options = JSON.parse(pollRow.options || '[]');
        const votes = db.prepare('SELECT option_index, user_id FROM poll_votes WHERE poll_id = ?').all(r.poll_id);
        const counts = options.map((_, i) => votes.filter(v => v.option_index === i).length);
        const myVotes = votes.filter(v => v.user_id === me).map(v => v.option_index);
        msg.poll = {
          id: pollRow.id,
          question: pollRow.question,
          options: options.map((text, i) => ({ text, votes: counts[i], voted: myVotes.includes(i) })),
          multiple: !!pollRow.multiple,
        };
      }
    }
    msg.reactions = getMessageReactions(r.id);
    return msg;
  });
  
  // Подсчитываем общее количество сообщений для пагинации
  const totalQuery = `
    SELECT COUNT(*) as cnt
    FROM messages
    WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
  `;
  const totalParams = [me, peerId, peerId, me];
  if (before && !Number.isNaN(before)) {
    // Если есть before, считаем только сообщения до этого ID
    const total = db.prepare(totalQuery + ' AND id < ?').get(...totalParams, before)?.cnt || 0;
    res.json({
      data: list,
      pagination: {
        limit,
        before,
        hasMore: list.length === limit,
        total,
      },
    });
  } else {
    const total = db.prepare(totalQuery).get(...totalParams)?.cnt || 0;
    res.json({
      data: list,
      pagination: {
        limit,
        hasMore: list.length === limit,
        total,
      },
    });
  }
}));

/**
 * @swagger
 * /messages:
 *   post:
 *     summary: Отправить сообщение
 *     tags: [Messages]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - receiver_id
 *             properties:
 *               receiver_id:
 *                 type: integer
 *               content:
 *                 type: string
 *                 maxLength: 10000
 *               type:
 *                 type: string
 *                 enum: [text, poll]
 *               reply_to_id:
 *                 type: integer
 *                 nullable: true
 *         multipart/form-data:
 *           schema:
 *             type: object
 *             properties:
 *               receiver_id:
 *                 type: integer
 *               content:
 *                 type: string
 *               file:
 *                 type: array
 *                 items:
 *                   type: string
 *                   format: binary
 *     responses:
 *       201:
 *         description: Сообщение отправлено
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Message'
 */
router.post('/', messageLimiter, uploadLimiter, (req, res, next) => {
  log.info({ path: req.path, method: req.method, contentType: req.get('Content-Type') }, 'POST /messages route handler - start');
  if (req.get('Content-Type')?.startsWith('multipart/form-data')) {
    log.info({ path: req.path, method: req.method }, 'POST /messages - processing multipart/form-data');
    return upload.array('file', FILE_LIMITS.MAX_FILES_PER_MESSAGE)(req, res, (err) => {
      if (err) {
        log.error({ path: req.path, method: req.method, error: err.message }, 'POST /messages - multer error');
        return res.status(400).json({ error: err.message || 'Ошибка загрузки файла' });
      }
      // Передаём files в body для валидации (custom validator проверяет content || files)
      req.body.files = req.files && Array.isArray(req.files) ? req.files : (req.file ? [req.file] : []);
      log.info({ path: req.path, method: req.method }, 'POST /messages - multer success, calling next()');
      next();
    });
  }
  log.info({ path: req.path, method: req.method }, 'POST /messages - not multipart, calling next()');
  next();
}, validate(sendMessageSchema), asyncHandler(async (req, res) => {
  log.info({ 
    path: req.path, 
    method: req.method, 
    userId: req.user?.userId,
    body: req.body,
    validated: req.validated 
  }, 'POST /messages route handler - after validation');
  const data = req.validated;
  const files = req.files && Array.isArray(req.files) ? req.files : (req.file ? [req.file] : []);
  const rid = Number(data.receiver_id);
  const me = Number(req.user.userId);
  if (isCommunicationBlocked(me, rid)) {
    return res.status(403).json({ error: 'Невозможно отправить сообщение этому пользователю' });
  }
  if (!canMessage(me, rid)) {
    return res.status(403).json({ error: 'Пользователь ограничил возможность писать ему' });
  }
  const isPoll = data.type === 'poll' && data.question && Array.isArray(data.options) && data.options.length >= 2;
  const isMissedCall = data.type === 'missed_call';
  const isLocation = data.type === 'location' && typeof data.lat === 'number' && typeof data.lng === 'number';
  const text = data.content ? sanitizeText(data.content) : '';
  if (!isPoll && !isMissedCall && !isLocation && !text && files.length === 0) return res.status(400).json({ error: 'content или файл обязательны' });
  const meUser = db.prepare('SELECT public_key FROM users WHERE id = ?').get(me);
  const baseUrl = getBaseUrl(req);
  const replyToId = data.reply_to_id || null;
  const isFwd = data.is_forwarded || false;
  const fwdFromId = data.forward_from_sender_id || null;
  const fwdFromName = data.forward_from_display_name ? sanitizeText(data.forward_from_display_name).slice(0, 128) : null;

  if (isPoll) {
    const options = data.options.slice(0, 10).map(o => sanitizeText(String(o))).filter(Boolean);
    if (options.length < 2) return res.status(400).json({ error: 'Минимум 2 варианта ответа' });
    const questionText = sanitizeText(data.question);
    let msgId; let pollId;
    try {
      // Используем транзакцию для атомарности операций
      const transaction = db.transaction(() => {
        const result = db.prepare(
          `INSERT INTO messages (sender_id, receiver_id, content, message_type, attachment_path, attachment_filename, sender_public_key) VALUES (?, ?, ?, 'poll', NULL, NULL, ?)`
        ).run(me, rid, questionText, meUser?.public_key ?? null);
        msgId = Number(result.lastInsertRowid);
        const pollResult = db.prepare(
          'INSERT INTO polls (message_id, question, options, multiple) VALUES (?, ?, ?, ?)'
        ).run(msgId, questionText, JSON.stringify(options), data.multiple ? 1 : 0);
        pollId = Number(pollResult.lastInsertRowid);
        db.prepare('UPDATE messages SET poll_id = ? WHERE id = ?').run(pollId, msgId);
      });
      transaction();
      // Вызываем syncMessagesFTS вне транзакции
      try {
        syncMessagesFTS(msgId);
      } catch (ftsErr) {
        log.warn({ err: ftsErr, msgId }, 'FTS sync error (non-critical)');
      }
    } catch (pollErr) {
      log.error({ err: pollErr, rid, me, code: pollErr.code, message: pollErr.message, stack: pollErr.stack }, 'POST /messages - poll creation error');
      throw pollErr;
    }
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, sender_public_key FROM messages WHERE id = ?'
    ).get(msgId);
    if (!row) {
      return res.status(500).json({ error: 'Ошибка при создании опроса' });
    }
    const payload = {
      id: row.id,
      sender_id: row.sender_id,
      receiver_id: row.receiver_id,
      content: questionText,
      created_at: row.created_at,
      read_at: row.read_at,
      is_mine: true,
      attachment_url: null,
      attachment_filename: null,
      message_type: 'poll',
      poll_id: pollId,
      sender_public_key: row.sender_public_key ?? meUser?.public_key ?? null,
      poll: {
        id: pollId,
        question: questionText,
        options: options.map((text, i) => ({ text, votes: 0, voted: false })),
        multiple: !!(data.multiple),
      },
      reactions: [],
    };
    notifyNewMessage(payload);
    return res.status(201).json(payload);
  }

  if (isLocation) {
    const locationContent = JSON.stringify({
      lat: data.lat,
      lng: data.lng,
      label: data.location_label ? sanitizeText(data.location_label).slice(0, 256) : null,
    });
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, message_type, sender_public_key) VALUES (?, ?, ?, 'location', ?)`
    ).run(me, rid, locationContent, meUser?.public_key ?? null);
    const msgId = result.lastInsertRowid;
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, sender_public_key FROM messages WHERE id = ?'
    ).get(msgId);
    const payload = {
      id: row.id,
      sender_id: row.sender_id,
      receiver_id: row.receiver_id,
      content: locationContent,
      created_at: row.created_at,
      read_at: row.read_at,
      is_mine: true,
      attachment_url: null,
      attachment_filename: null,
      message_type: 'location',
      poll_id: null,
      sender_public_key: row.sender_public_key ?? meUser?.public_key ?? null,
      reactions: [],
    };
    notifyNewMessage(payload);
    return res.status(201).json(payload);
  }

  const attachmentKind = (files.length <= 1 && (req.body?.attachment_kind === 'voice' || req.body?.attachment_kind === 'video_note'))
    ? req.body.attachment_kind
    : 'file';
  const attachmentDurationSec = req.body?.attachment_duration_sec != null
    ? parseInt(req.body.attachment_duration_sec, 10)
    : null;
  const attachmentEncrypted = req.body?.attachment_encrypted === 'true' || req.body?.attachment_encrypted === true ? 1 : 0;

  function buildPayload(row) {
    const payload = {
      ...row,
      content: row.content,
      is_mine: true,
      attachment_url: row.attachment_path ? `${baseUrl}/uploads/${row.attachment_path}` : null,
      attachment_filename: row.attachment_filename || null,
      message_type: row.message_type || 'text',
      poll_id: row.poll_id ?? null,
      attachment_kind: row.attachment_kind || 'file',
      attachment_duration_sec: row.attachment_duration_sec ?? null,
      attachment_encrypted: !!(row.attachment_encrypted),
      sender_public_key: row.sender_public_key ?? meUser?.public_key ?? null,
      reply_to_id: row.reply_to_id ?? null,
      is_forwarded: !!(row.is_forwarded),
      forward_from_sender_id: row.forward_from_sender_id ?? null,
      forward_from_display_name: row.forward_from_display_name ?? null,
    };
    if (row.reply_to_id) {
      const replyRow = db.prepare('SELECT content, sender_id FROM messages WHERE id = ?').get(row.reply_to_id);
      if (replyRow) {
        const replySender = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(replyRow.sender_id);
        payload.reply_to_content = (replyRow.content || '').length > 80 ? (replyRow.content || '').slice(0, 77) + '...' : (replyRow.content || '');
        payload.reply_to_sender_name = replySender?.display_name || replySender?.username || '?';
      }
    }
    payload.reactions = getMessageReactions(row.id);
    return payload;
  }

  if (files.length === 0) {
    const contentToStore = isMissedCall ? 'Пропущенный звонок' : (text || '');
    const messageType = isMissedCall ? 'missed_call' : 'text';
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(me, rid, contentToStore, null, null, messageType, attachmentKind, attachmentDurationSec, attachmentEncrypted, replyToId, isFwd ? 1 : 0, fwdFromId, fwdFromName, meUser?.public_key ?? null);
    const msgId = result.lastInsertRowid;
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key FROM messages WHERE id = ?'
    ).get(msgId);
    if (!row) {
      return res.status(500).json({ error: 'Ошибка при создании сообщения' });
    }
    const payload = buildPayload(row);
    notifyNewMessage(payload);
    return res.status(201).json(payload);
  }

  const payloads = [];
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    let attachmentPath = file.filename;
    const fullPath = path.join(uploadsDir, file.filename);
    
    // Проверка файла на безопасность
    const fileValidation = await validateFile(fullPath);
    if (!fileValidation.valid) {
      // Удаляем небезопасный файл
      try { fs.unlinkSync(fullPath); } catch (_) {}
      return res.status(400).json({ error: fileValidation.error || 'Файл не прошёл проверку безопасности' });
    }
    
    try {
      const stat = fs.statSync(fullPath);
      if (stat.size >= FILE_LIMITS.MIN_SIZE_TO_COMPRESS) {
        const data = fs.readFileSync(fullPath);
        const compressed = zlib.gzipSync(data);
        fs.writeFileSync(fullPath + '.gz', compressed);
        fs.unlinkSync(fullPath);
        attachmentPath = file.filename + '.gz';
      }
    } catch (_) {}
    const attachmentFilename = file.originalname || null;
    const contentToStore = i === 0 && text ? text : (attachmentKind === 'voice' ? 'Голосовое сообщение' : attachmentKind === 'video_note' ? 'Видеокружок' : '(файл)');
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key) VALUES (?, ?, ?, ?, ?, 'text', ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(me, rid, contentToStore, attachmentPath, attachmentFilename, attachmentKind, attachmentDurationSec, attachmentEncrypted, i === 0 && !Number.isNaN(replyToId) ? replyToId : null, isFwd ? 1 : 0, fwdFromId, fwdFromName, meUser?.public_key ?? null);
    const msgId = result.lastInsertRowid;
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key FROM messages WHERE id = ?'
    ).get(msgId);
    if (!row) {
      log.error('Failed to retrieve created message after file upload', { msgId, fileIndex: i });
      // Пропускаем этот файл, но продолжаем обработку остальных
      continue;
    }
    const payload = buildPayload(row);
    notifyNewMessage(payload);
    payloads.push(payload);
  }
  
  if (payloads.length === 0) {
    return res.status(500).json({ error: 'Не удалось создать сообщения с файлами' });
  }
  
  if (payloads.length === 1) return res.status(201).json(payloads[0]);
  return res.status(201).json({ messages: payloads });
}));

// Удаление сообщения: for_me=true — только для себя, иначе — для всех
router.delete('/:messageId', validateParams(messageIdParamSchema), asyncHandler(async (req, res) => {
  const messageId = Number(req.validatedParams.messageId);
  const forMe = req.query.for_me === 'true' || req.query.for_me === '1';
  const me = Number(req.user.userId);
  
  const message = db.prepare('SELECT id, sender_id, receiver_id FROM messages WHERE id = ?').get(messageId);
  if (!message) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }
  
  if (Number(message.sender_id) !== me && Number(message.receiver_id) !== me) {
    return res.status(403).json({ error: 'Нет доступа к сообщению' });
  }
  
  if (forMe) {
    try {
      db.prepare('INSERT OR IGNORE INTO message_deleted_for (user_id, message_id) VALUES (?, ?)').run(Number(me), Number(messageId));
    } catch (e) {
      if (e.message && e.message.includes('message_deleted_for')) {
        return res.status(501).json({ error: 'Функция «удалить для себя» не поддерживается' });
      }
      log.error({ err: e, messageId, me, code: e.code, message: e.message, stack: e.stack }, 'DELETE /messages/:messageId (forMe) - DB error');
      throw e;
    }
    return res.status(204).send();
  }
  
  // Удаление для всех - используем транзакцию для атомарности
  // Порядок важен: сначала удаляем зависимые записи, потом само сообщение
  try {
    const transaction = db.transaction(() => {
      // Сначала удаляем голоса в опросах, если есть опрос (до удаления опроса)
      const poll = db.prepare('SELECT id FROM polls WHERE message_id = ?').get(messageId);
      if (poll && poll.id != null) {
        const pollId = Number(poll.id);
        if (!isNaN(pollId) && pollId > 0) {
          db.prepare('DELETE FROM poll_votes WHERE poll_id = ?').run(pollId);
          db.prepare('DELETE FROM polls WHERE id = ?').run(pollId);
        }
      }
      // Удаляем реакции (CASCADE должен удалить автоматически, но делаем явно для надежности)
      db.prepare('DELETE FROM message_reactions WHERE message_id = ?').run(messageId);
      // Удаляем записи о скрытии сообщения
      db.prepare('DELETE FROM message_deleted_for WHERE message_id = ?').run(messageId);
      // Удаляем из FTS индекса (может не существовать)
      try {
        db.prepare('DELETE FROM messages_fts WHERE rowid = ?').run(messageId);
      } catch (ftsErr) {
        // Игнорируем ошибки FTS
      }
      // В конце удаляем само сообщение (CASCADE удалит связанные записи автоматически)
      const deleteResult = db.prepare('DELETE FROM messages WHERE id = ?').run(messageId);
      if (deleteResult.changes === 0) {
        throw new Error('Message not found or already deleted');
      }
    });
    transaction();
  } catch (err) {
    log.error({ err, messageId, me, code: err.code, message: err.message, stack: err.stack }, 'DELETE /messages/:messageId - DB error');
    throw err;
  }
  
  // Уведомляем другого пользователя о удалении (если это не групповое сообщение)
  try {
    const otherUserId = Number(message.sender_id) === me ? Number(message.receiver_id) : Number(message.sender_id);
    const peerIdForOther = me; // для получателя peer в этом чате — тот, кто удалил (отправитель)
    if (otherUserId && otherUserId > 0) {
      const { notifyMessageDeleted } = await import('../realtime.js');
      notifyMessageDeleted(otherUserId, messageId, peerIdForOther);
    }
  } catch (notifyErr) {
    // Логируем ошибку уведомления, но не прерываем выполнение
    log.warn({ err: notifyErr, messageId, me }, 'DELETE /messages/:messageId - notification error (non-critical)');
  }
  
  res.status(204).send();
}));

export default router;
