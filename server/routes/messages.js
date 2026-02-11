import { Router } from 'express';
import multer from 'multer';
import { randomUUID } from 'crypto';
import path from 'path';
import fs from 'fs';
import zlib from 'zlib';
import { fileURLToPath } from 'url';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { notifyNewMessage, notifyReaction } from '../realtime.js';
import { decryptIfLegacy } from '../cipher.js';
import { messageLimiter, uploadLimiter } from '../middleware/rateLimit.js';
import { sanitizeText } from '../middleware/sanitize.js';
import { validate, sendMessageSchema, validateParams, peerIdParamSchema, messageIdParamSchema, addReactionSchema } from '../middleware/validation.js';
import { validateFile } from '../middleware/fileValidation.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { ALLOWED_REACTION_EMOJIS, FILE_LIMITS, ALLOWED_FILE_TYPES } from '../config/constants.js';
import { syncMessagesFTS } from '../utils/ftsSync.js';
import { log } from '../utils/logger.js';
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
  const peerId = req.validatedParams.peerId;
  const me = req.user.userId;
  db.prepare(
    'UPDATE messages SET read_at = CURRENT_TIMESTAMP WHERE receiver_id = ? AND sender_id = ? AND read_at IS NULL'
  ).run(me, peerId);
  res.status(204).send();
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
  const baseUrl = getBaseUrl(req);

  let query = `
    SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name
    FROM messages
    WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
  `;
  const params = [me, peerId, peerId, me];
  if (before && !Number.isNaN(before)) {
    query += ' AND id < ?';
    params.push(before);
  }
  query += ' ORDER BY id DESC LIMIT ?';
  params.push(limit);

  const rows = db.prepare(query).all(...params);
  const list = rows.reverse().map(r => {
    const sender = db.prepare('SELECT public_key FROM users WHERE id = ?').get(r.sender_id);
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
      sender_public_key: sender?.public_key ?? null,
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
      log.info({ path: req.path, method: req.method }, 'POST /messages - multer success, calling next()');
      next();
    });
  }
  log.info({ path: req.path, method: req.method }, 'POST /messages - not multipart, calling next()');
  next();
}), (req, res, next) => {
  log.info({ path: req.path, method: req.method }, 'POST /messages - before validation');
  next();
}, validate(sendMessageSchema), (req, res, next) => {
  log.info({ path: req.path, method: req.method }, 'POST /messages - after validation, before handler');
  next();
}, asyncHandler(async (req, res) => {
  log.info({ path: req.path, method: req.method }, 'POST /messages route handler - after validation');
  const data = req.validated;
  const files = req.files && Array.isArray(req.files) ? req.files : (req.file ? [req.file] : []);
  const rid = data.receiver_id;
  const isPoll = data.type === 'poll' && data.question && Array.isArray(data.options) && data.options.length >= 2;
  const isMissedCall = data.type === 'missed_call';
  const text = data.content ? sanitizeText(data.content) : '';
  if (!isPoll && !isMissedCall && !text && files.length === 0) return res.status(400).json({ error: 'content или файл обязательны' });
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const replyToId = data.reply_to_id || null;
  const isFwd = data.is_forwarded || false;
  const fwdFromId = data.forward_from_sender_id || null;
  const fwdFromName = data.forward_from_display_name ? sanitizeText(data.forward_from_display_name).slice(0, 128) : null;

  if (isPoll) {
    const options = data.options.slice(0, 10).map(o => sanitizeText(String(o))).filter(Boolean);
    if (options.length < 2) return res.status(400).json({ error: 'Минимум 2 варианта ответа' });
    const questionText = sanitizeText(data.question);
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, message_type, attachment_path, attachment_filename) VALUES (?, ?, ?, 'poll', NULL, NULL)`
    ).run(me, rid, questionText);
    const msgId = result.lastInsertRowid;
    const pollResult = db.prepare(
      'INSERT INTO polls (message_id, question, options, multiple) VALUES (?, ?, ?, ?)'
    ).run(msgId, questionText, JSON.stringify(options), data.multiple ? 1 : 0);
    const pollId = pollResult.lastInsertRowid;
    db.prepare('UPDATE messages SET poll_id = ? WHERE id = ?').run(pollId, msgId);
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id FROM messages WHERE id = ?'
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

  const attachmentKind = (files.length <= 1 && (req.body?.attachment_kind === 'voice' || req.body?.attachment_kind === 'video_note'))
    ? req.body.attachment_kind
    : 'file';
  const attachmentDurationSec = req.body?.attachment_duration_sec != null
    ? parseInt(req.body.attachment_duration_sec, 10)
    : null;
  const attachmentEncrypted = req.body?.attachment_encrypted === 'true' || req.body?.attachment_encrypted === true ? 1 : 0;
  const meUser = db.prepare('SELECT public_key FROM users WHERE id = ?').get(me);

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
      sender_public_key: meUser?.public_key ?? null,
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
      `INSERT INTO messages (sender_id, receiver_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(me, rid, contentToStore, null, null, messageType, attachmentKind, attachmentDurationSec, attachmentEncrypted, replyToId, isFwd ? 1 : 0, fwdFromId, fwdFromName);
    const msgId = result.lastInsertRowid;
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name FROM messages WHERE id = ?'
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
      `INSERT INTO messages (sender_id, receiver_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name) VALUES (?, ?, ?, ?, ?, 'text', ?, ?, ?, ?, ?, ?, ?)`
    ).run(me, rid, contentToStore, attachmentPath, attachmentFilename, attachmentKind, attachmentDurationSec, attachmentEncrypted, i === 0 && !Number.isNaN(replyToId) ? replyToId : null, isFwd ? 1 : 0, fwdFromId, fwdFromName);
    const msgId = result.lastInsertRowid;
    syncMessagesFTS(msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name FROM messages WHERE id = ?'
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
});

// Удаление сообщения (для всех участников)
router.delete('/:messageId', validateParams(messageIdParamSchema), asyncHandler(async (req, res) => {
  const messageId = req.validatedParams.messageId;
  const me = req.user.userId;
  
  // Проверяем, что сообщение существует и принадлежит пользователю
  const message = db.prepare('SELECT id, sender_id, receiver_id FROM messages WHERE id = ?').get(messageId);
  if (!message) {
    return res.status(404).json({ error: 'Сообщение не найдено' });
  }
  
  // Проверяем, что пользователь является отправителем или получателем
  if (message.sender_id !== me && message.receiver_id !== me) {
    return res.status(403).json({ error: 'Нет доступа к сообщению' });
  }
  
  // Удаляем сообщение из БД
  db.prepare('DELETE FROM messages WHERE id = ?').run(messageId);
  
  // Удаляем связанные данные (реакции, опросы)
  db.prepare('DELETE FROM message_reactions WHERE message_id = ?').run(messageId);
  const poll = db.prepare('SELECT id FROM polls WHERE message_id = ?').get(messageId);
  if (poll) {
    db.prepare('DELETE FROM poll_votes WHERE poll_id = ?').run(poll.id);
    db.prepare('DELETE FROM polls WHERE id = ?').run(poll.id);
  }
  
  // Удаляем из FTS индекса
  try {
    db.prepare('DELETE FROM messages_fts WHERE rowid = ?').run(messageId);
  } catch (_) {}
  
  // Уведомляем другого участника чата об удалении
  const otherUserId = message.sender_id === me ? message.receiver_id : message.sender_id;
  const { notifyMessageDeleted } = await import('../realtime.js');
  notifyMessageDeleted(otherUserId, messageId);
  
  res.status(204).send();
}));

export default router;
