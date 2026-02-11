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

const ALLOWED_EMOJIS = new Set(['👍', '👎', '❤️', '🔥', '😂', '😮', '😢']);
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
const MIN_SIZE_TO_COMPRESS = 100 * 1024; // 100 KB — мелкие не трогаем

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
  limits: { fileSize: 100 * 1024 * 1024 }, // 100 MB
  fileFilter: (req, file, cb) => {
    const ext = (path.extname(file.originalname) || '').toLowerCase();
    const blocked = ['.exe', '.bat', '.cmd', '.sh', '.dll', '.so', '.dylib'];
    if (blocked.some(b => ext === b)) return cb(new Error('Тип файла не разрешён'));
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

router.patch('/:peerId/read', (req, res) => {
  const peerId = parseInt(req.params.peerId, 10);
  if (Number.isNaN(peerId)) return res.status(400).json({ error: 'Некорректный id чата' });
  const me = req.user.userId;
  db.prepare(
    'UPDATE messages SET read_at = CURRENT_TIMESTAMP WHERE receiver_id = ? AND sender_id = ? AND read_at IS NULL'
  ).run(me, peerId);
  res.status(204).send();
});

router.post('/:messageId/reaction', (req, res) => {
  const messageId = parseInt(req.params.messageId, 10);
  const emoji = typeof req.body?.emoji === 'string' ? req.body.emoji.trim() : '';
  if (Number.isNaN(messageId) || messageId < 1) return res.status(400).json({ error: 'Некорректный id сообщения' });
  if (!ALLOWED_EMOJIS.has(emoji)) return res.status(400).json({ error: 'Недопустимая реакция' });
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
});

router.get('/:peerId', (req, res) => {
  const peerId = parseInt(req.params.peerId, 10);
  if (Number.isNaN(peerId)) {
    return res.status(400).json({ error: 'Некорректный id чата' });
  }
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
  res.json(list);
});

router.post('/', messageLimiter, uploadLimiter, (req, res, next) => {
  if (req.get('Content-Type')?.startsWith('multipart/form-data')) {
    return upload.array('file', 20)(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Ошибка загрузки файла' });
      next();
    });
  }
  next();
}, (req, res) => {
  const { receiver_id, content, type, question, options: optArr, multiple, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name } = req.body;
  const rid = parseInt(receiver_id, 10);
  const isPoll = type === 'poll' && question && Array.isArray(optArr) && optArr.length >= 2;
  const text = (content ?? '').trim();
  const files = req.files && Array.isArray(req.files) ? req.files : (req.file ? [req.file] : []);
  if (Number.isNaN(rid)) return res.status(400).json({ error: 'receiver_id обязателен' });
  if (!isPoll && !text && files.length === 0) return res.status(400).json({ error: 'content или файл обязательны' });
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const replyToId = reply_to_id != null ? parseInt(reply_to_id, 10) : null;
  const isFwd = is_forwarded === true || is_forwarded === 'true';
  const fwdFromId = forward_from_sender_id != null ? parseInt(forward_from_sender_id, 10) : null;
  const fwdFromName = typeof forward_from_display_name === 'string' ? forward_from_display_name.trim().slice(0, 128) : null;

  if (isPoll) {
    const options = optArr.slice(0, 10).map(o => String(o).trim()).filter(Boolean);
    if (options.length < 2) return res.status(400).json({ error: 'Минимум 2 варианта ответа' });
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, message_type, attachment_path, attachment_filename) VALUES (?, ?, ?, 'poll', NULL, NULL)`
    ).run(me, rid, question);
    const msgId = result.lastInsertRowid;
    const pollResult = db.prepare(
      'INSERT INTO polls (message_id, question, options, multiple) VALUES (?, ?, ?, ?)'
    ).run(msgId, question, JSON.stringify(options), multiple ? 1 : 0);
    const pollId = pollResult.lastInsertRowid;
    db.prepare('UPDATE messages SET poll_id = ? WHERE id = ?').run(pollId, msgId);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id FROM messages WHERE id = ?'
    ).get(msgId);
    const payload = {
      id: row.id,
      sender_id: row.sender_id,
      receiver_id: row.receiver_id,
      content: question,
      created_at: row.created_at,
      read_at: row.read_at,
      is_mine: true,
      attachment_url: null,
      attachment_filename: null,
      message_type: 'poll',
      poll_id: pollId,
      poll: {
        id: pollId,
        question,
        options: options.map((text, i) => ({ text, votes: 0, voted: false })),
        multiple: !!multiple,
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
    const contentToStore = text || '';
    const result = db.prepare(
      `INSERT INTO messages (sender_id, receiver_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name) VALUES (?, ?, ?, ?, ?, 'text', ?, ?, ?, ?, ?, ?, ?)`
    ).run(me, rid, contentToStore, null, null, attachmentKind, attachmentDurationSec, attachmentEncrypted, Number.isNaN(replyToId) ? null : replyToId, isFwd ? 1 : 0, fwdFromId, fwdFromName);
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name FROM messages WHERE id = ?'
    ).get(result.lastInsertRowid);
    const payload = buildPayload(row);
    notifyNewMessage(payload);
    return res.status(201).json(payload);
  }

  const payloads = [];
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    let attachmentPath = file.filename;
    const fullPath = path.join(uploadsDir, file.filename);
    try {
      const stat = fs.statSync(fullPath);
      if (stat.size >= MIN_SIZE_TO_COMPRESS) {
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
    const row = db.prepare(
      'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name FROM messages WHERE id = ?'
    ).get(result.lastInsertRowid);
    const payload = buildPayload(row);
    notifyNewMessage(payload);
    payloads.push(payload);
  }
  if (payloads.length === 1) return res.status(201).json(payloads[0]);
  return res.status(201).json({ messages: payloads });
});

export default router;
