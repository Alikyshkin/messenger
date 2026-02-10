import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import zlib from 'zlib';
import { randomUUID } from 'crypto';
import { fileURLToPath } from 'url';
import { mkdirSync, existsSync, unlinkSync } from 'fs';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { notifyNewGroupMessage } from '../realtime.js';
import { decryptIfLegacy } from '../cipher.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const uploadsDir = path.join(__dirname, '../uploads');
const groupAvatarsDir = path.join(uploadsDir, 'group_avatars');
const MIN_SIZE_TO_COMPRESS = 100 * 1024;

if (!existsSync(groupAvatarsDir)) mkdirSync(groupAvatarsDir, { recursive: true });

const groupAvatarUpload = multer({
  storage: multer.diskStorage({
    destination: groupAvatarsDir,
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

const fileUpload = multer({
  storage: multer.diskStorage({
    destination: uploadsDir,
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname) || '';
      const safe = (ext && /^\.\w+$/.test(ext)) ? ext : '';
      cb(null, randomUUID() + safe);
    },
  }),
  limits: { fileSize: 100 * 1024 * 1024 },
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

function groupToJson(group, baseUrl, options = {}) {
  const j = {
    id: group.id,
    name: group.name,
    avatar_url: group.avatar_path ? `${baseUrl}/uploads/group_avatars/${group.avatar_path}` : null,
    created_by_user_id: group.created_by_user_id,
    created_at: group.created_at,
  };
  if (options.members) j.members = options.members;
  if (options.my_role) j.my_role = options.my_role;
  if (options.member_count !== undefined) j.member_count = options.member_count;
  return j;
}

function getGroupMemberIds(groupId) {
  return db.prepare('SELECT user_id FROM group_members WHERE group_id = ?').all(groupId).map((r) => r.user_id);
}

function isMember(me, groupId) {
  return db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, me);
}

function isAdmin(me, groupId) {
  const row = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, me);
  return row?.role === 'admin';
}

// Список групп текущего пользователя (для чатов объединим в chats.js)
router.get('/', (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const rows = db.prepare(`
    SELECT g.id, g.name, g.avatar_path, g.created_by_user_id, g.created_at,
           gm.role AS my_role
    FROM groups g
    JOIN group_members gm ON g.id = gm.group_id AND gm.user_id = ?
    ORDER BY g.id
  `).all(me);
  const list = rows.map((r) => {
    const count = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(r.id);
    return groupToJson(
      { id: r.id, name: r.name, avatar_path: r.avatar_path, created_by_user_id: r.created_by_user_id, created_at: r.created_at },
      baseUrl,
      { my_role: r.my_role, member_count: count?.c ?? 0 },
    );
  });
  res.json(list);
});

// Создать группу: body { name, member_ids: number[] }, опционально multipart avatar
router.post('/', (req, res, next) => {
  if (req.get('Content-Type')?.startsWith('multipart/form-data')) {
    return groupAvatarUpload.single('avatar')(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Ошибка загрузки' });
      next();
    });
  }
  next();
}, (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  let name = (req.body?.name ?? '').trim();
  let memberIds = req.body?.member_ids;
  if (!name) return res.status(400).json({ error: 'Укажите название группы' });
  if (name.length > 128) name = name.slice(0, 128);
  if (!Array.isArray(memberIds)) memberIds = [];
  memberIds = [...new Set(memberIds.map((id) => parseInt(id, 10)).filter((id) => !Number.isNaN(id) && id !== me))];
  const avatarPath = req.file?.filename ?? null;

  const insertGroup = db.prepare(
    'INSERT INTO groups (name, avatar_path, created_by_user_id) VALUES (?, ?, ?)',
  );
  const insertMember = db.prepare(
    'INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)',
  );
  const insertRead = db.prepare(
    'INSERT INTO group_read (group_id, user_id, last_read_message_id) VALUES (?, ?, 0)',
  );

  const run = db.transaction(() => {
    const result = insertGroup.run(name, avatarPath, me);
    const groupId = result.lastInsertRowid;
    insertMember.run(groupId, me, 'admin');
    insertRead.run(groupId, me);
    memberIds.forEach((uid) => {
      insertMember.run(groupId, uid, 'member');
      insertRead.run(groupId, uid);
    });
    return groupId;
  });
  const groupId = run();
  const group = db.prepare('SELECT id, name, avatar_path, created_by_user_id, created_at FROM groups WHERE id = ?').get(groupId);
  const memberCount = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(groupId);
  const payload = groupToJson(group, baseUrl, { my_role: 'admin', member_count: memberCount?.c ?? 0 });
  res.status(201).json(payload);
});

// Информация о группе и участники
router.get('/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: 'Некорректный id группы' });
  const me = req.user.userId;
  if (!isMember(me, id)) return res.status(404).json({ error: 'Группа не найдена' });
  const baseUrl = getBaseUrl(req);
  const group = db.prepare('SELECT id, name, avatar_path, created_by_user_id, created_at FROM groups WHERE id = ?').get(id);
  if (!group) return res.status(404).json({ error: 'Группа не найдена' });
  const myRow = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND user_id = ?').get(id, me);
  const memberRows = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.avatar_path, u.public_key, gm.role
    FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = ?
    ORDER BY gm.role DESC, u.display_name, u.username
  `).all(id);
  const members = memberRows.map((u) => ({
    id: u.id,
    username: u.username,
    display_name: u.display_name || u.username,
    avatar_url: u.avatar_path ? `${baseUrl}/uploads/avatars/${u.avatar_path}` : null,
    public_key: u.public_key ?? null,
    role: u.role,
  }));
  res.json(groupToJson(group, baseUrl, { members, my_role: myRow?.role }));
});

// Обновить название и/или фото (только админ)
router.patch('/:id', (req, res, next) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: 'Некорректный id группы' });
  const me = req.user.userId;
  if (!isAdmin(me, id)) return res.status(403).json({ error: 'Только администратор может изменить группу' });
  if (req.get('Content-Type')?.startsWith('multipart/form-data')) {
    return groupAvatarUpload.single('avatar')(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Ошибка загрузки' });
      next();
    });
  }
  next();
}, (req, res) => {
  const id = parseInt(req.params.id, 10);
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  const name = typeof req.body?.name === 'string' ? req.body.name.trim().slice(0, 128) : null;
  const avatarPath = req.file?.filename ?? null;
  if (!name && !avatarPath) return res.status(400).json({ error: 'Укажите name и/или загрузите avatar' });
  const group = db.prepare('SELECT id, name, avatar_path, created_by_user_id, created_at FROM groups WHERE id = ?').get(id);
  if (!group) return res.status(404).json({ error: 'Группа не найдена' });
  if (name) {
    db.prepare('UPDATE groups SET name = ? WHERE id = ?').run(name, id);
    group.name = name;
  }
  if (avatarPath) {
    if (group.avatar_path) {
      const oldPath = path.join(groupAvatarsDir, group.avatar_path);
      if (existsSync(oldPath)) try { unlinkSync(oldPath); } catch (_) {}
    }
    db.prepare('UPDATE groups SET avatar_path = ? WHERE id = ?').run(avatarPath, id);
    group.avatar_path = avatarPath;
  }
  const memberCount = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(id);
  const myRow = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND user_id = ?').get(id, me);
  res.json(groupToJson(group, baseUrl, { my_role: myRow?.role, member_count: memberCount?.c ?? 0 }));
});

// Добавить участников (админ)
router.post('/:id/members', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: 'Некорректный id группы' });
  const me = req.user.userId;
  if (!isAdmin(me, id)) return res.status(403).json({ error: 'Только администратор может добавлять участников' });
  let userIds = req.body?.user_ids;
  if (!Array.isArray(userIds)) userIds = [];
  userIds = [...new Set(userIds.map((u) => parseInt(u, 10)).filter((u) => !Number.isNaN(u) && u !== me))];
  const insertMember = db.prepare('INSERT OR IGNORE INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)');
  const insertRead = db.prepare(
    'INSERT OR IGNORE INTO group_read (group_id, user_id, last_read_message_id) VALUES (?, ?, 0)',
  );
  const getMaxId = db.prepare('SELECT COALESCE(MAX(id), 0) AS mid FROM group_messages WHERE group_id = ?');
  const maxId = getMaxId.get(id)?.mid ?? 0;
  userIds.forEach((uid) => {
    insertMember.run(id, uid, 'member');
    insertRead.run(id, uid);
  });
  res.status(204).send();
});

// Удалить участника или выйти (админ может удалить любого, участник — только себя)
router.delete('/:id/members/:userId', (req, res) => {
  const groupId = parseInt(req.params.id, 10);
  const userId = parseInt(req.params.userId, 10);
  if (Number.isNaN(groupId) || Number.isNaN(userId)) return res.status(400).json({ error: 'Некорректный id' });
  const me = req.user.userId;
  if (!isMember(me, groupId)) return res.status(404).json({ error: 'Группа не найдена' });
  if (me !== userId && !isAdmin(me, groupId)) {
    return res.status(403).json({ error: 'Можно удалить только себя или быть админом' });
  }
  db.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').run(groupId, userId);
  db.prepare('DELETE FROM group_read WHERE group_id = ? AND user_id = ?').run(groupId, userId);
  const left = db.prepare('SELECT COUNT(*) AS c FROM group_members WHERE group_id = ?').get(groupId)?.c ?? 0;
  if (left === 0) {
    db.prepare('DELETE FROM group_messages WHERE group_id = ?').run(groupId);
    db.prepare('DELETE FROM groups WHERE id = ?').run(groupId);
  }
  res.status(204).send();
});

// Прочитать сообщения группы
router.get('/:id/messages', (req, res) => {
  const groupId = parseInt(req.params.id, 10);
  if (Number.isNaN(groupId)) return res.status(400).json({ error: 'Некорректный id группы' });
  const me = req.user.userId;
  if (!isMember(me, groupId)) return res.status(404).json({ error: 'Группа не найдена' });
  const limit = Math.min(parseInt(req.query.limit, 10) || 100, 200);
  const before = req.query.before ? parseInt(req.query.before, 10) : null;
  const baseUrl = getBaseUrl(req);

  let query = `
    SELECT id, group_id, sender_id, content, created_at, attachment_path, attachment_filename, message_type,
           attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name
    FROM group_messages
    WHERE group_id = ?
  `;
  const params = [groupId];
  if (before && !Number.isNaN(before)) {
    query += ' AND id < ?';
    params.push(before);
  }
  query += ' ORDER BY id DESC LIMIT ?';
  params.push(limit);

  const rows = db.prepare(query).all(...params);
  const list = rows.reverse().map((r) => {
    const sender = db.prepare('SELECT public_key, display_name, username FROM users WHERE id = ?').get(r.sender_id);
    const msg = {
      id: r.id,
      group_id: r.group_id,
      sender_id: r.sender_id,
      sender_display_name: sender?.display_name || sender?.username || '?',
      content: decryptIfLegacy(r.content),
      created_at: r.created_at,
      is_mine: r.sender_id === me,
      attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
      attachment_filename: r.attachment_filename || null,
      message_type: r.message_type || 'text',
      poll_id: null,
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
      const replyRow = db.prepare('SELECT content, sender_id FROM group_messages WHERE id = ?').get(r.reply_to_id);
      if (replyRow) {
        const replySender = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(replyRow.sender_id);
        let snippet = replyRow.content || '';
        if (snippet.length > 80) snippet = snippet.slice(0, 77) + '...';
        msg.reply_to_content = snippet;
        msg.reply_to_sender_name = replySender?.display_name || replySender?.username || '?';
      }
    }
    const pollRow = db.prepare('SELECT id, question, options, multiple FROM group_polls WHERE group_message_id = ?').get(r.id);
    if (pollRow) {
      msg.poll_id = pollRow.id;
      const options = JSON.parse(pollRow.options || '[]');
      const votes = db.prepare('SELECT option_index, user_id FROM group_poll_votes WHERE group_poll_id = ?').all(pollRow.id);
      const counts = options.map((_, i) => votes.filter((v) => v.option_index === i).length);
      const myVotes = votes.filter((v) => v.user_id === me).map((v) => v.option_index);
      msg.poll = {
        id: pollRow.id,
        question: pollRow.question,
        options: options.map((text, i) => ({ text, votes: counts[i], voted: myVotes.includes(i) })),
        multiple: !!pollRow.multiple,
      };
    }
    return msg;
  });
  res.json(list);
});

// Отметить прочтение
router.patch('/:id/read', (req, res) => {
  const groupId = parseInt(req.params.id, 10);
  const lastMessageId = parseInt(req.body?.last_message_id, 10);
  if (Number.isNaN(groupId)) return res.status(400).json({ error: 'Некорректный id группы' });
  if (Number.isNaN(lastMessageId) || lastMessageId < 0) return res.status(400).json({ error: 'Укажите last_message_id' });
  const me = req.user.userId;
  if (!isMember(me, groupId)) return res.status(404).json({ error: 'Группа не найдена' });
  const existing = db.prepare('SELECT last_read_message_id FROM group_read WHERE group_id = ? AND user_id = ?').get(groupId, me);
  const newId = existing
    ? Math.max(existing.last_read_message_id, lastMessageId)
    : lastMessageId;
  if (existing) {
    db.prepare('UPDATE group_read SET last_read_message_id = ? WHERE group_id = ? AND user_id = ?').run(newId, groupId, me);
  } else {
    db.prepare('INSERT INTO group_read (group_id, user_id, last_read_message_id) VALUES (?, ?, ?)').run(groupId, me, newId);
  }
  res.status(204).send();
});

// Отправить сообщение в группу (текст, файл, опрос)
router.post('/:id/messages', (req, res, next) => {
  if (req.get('Content-Type')?.startsWith('multipart/form-data')) {
    return fileUpload.single('file')(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || 'Ошибка загрузки файла' });
      next();
    });
  }
  next();
}, (req, res) => {
  const groupId = parseInt(req.params.id, 10);
  if (Number.isNaN(groupId)) return res.status(400).json({ error: 'Некорректный id группы' });
  const me = req.user.userId;
  if (!isMember(me, groupId)) return res.status(404).json({ error: 'Группа не найдена' });
  const baseUrl = getBaseUrl(req);
  const {
    content,
    type,
    question,
    options: optArr,
    multiple,
    reply_to_id,
    is_forwarded,
    forward_from_sender_id,
    forward_from_display_name,
  } = req.body || {};
  const isPoll = type === 'poll' && question && Array.isArray(optArr) && optArr.length >= 2;
  const text = (content ?? '').trim();
  if (!isPoll && !text && !req.file) return res.status(400).json({ error: 'content или файл обязательны' });
  const replyToId = reply_to_id != null ? parseInt(reply_to_id, 10) : null;
  const isFwd = is_forwarded === true || is_forwarded === 'true';
  const fwdFromId = forward_from_sender_id != null ? parseInt(forward_from_sender_id, 10) : null;
  const fwdFromName = typeof forward_from_display_name === 'string' ? forward_from_display_name.trim().slice(0, 128) : null;

  if (isPoll) {
    const options = optArr.slice(0, 10).map((o) => String(o).trim()).filter(Boolean);
    if (options.length < 2) return res.status(400).json({ error: 'Минимум 2 варианта ответа' });
    const insMsg = db.prepare(
      `INSERT INTO group_messages (group_id, sender_id, content, message_type) VALUES (?, ?, ?, 'poll')`,
    ).run(groupId, me, question);
    const msgId = insMsg.lastInsertRowid;
    const pollResult = db.prepare(
      'INSERT INTO group_polls (group_message_id, question, options, multiple) VALUES (?, ?, ?, ?)',
    ).run(msgId, question, JSON.stringify(options), multiple ? 1 : 0);
    const pollId = pollResult.lastInsertRowid;
    const row = db.prepare(
      'SELECT id, group_id, sender_id, content, created_at, message_type FROM group_messages WHERE id = ?',
    ).get(msgId);
    const sender = db.prepare('SELECT public_key, display_name, username FROM users WHERE id = ?').get(me);
    const payload = {
      id: row.id,
      group_id: row.group_id,
      sender_id: row.sender_id,
      sender_display_name: sender?.display_name || sender?.username || '?',
      content: row.content,
      created_at: row.created_at,
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
      reply_to_id: null,
      is_forwarded: false,
      forward_from_sender_id: null,
      forward_from_display_name: null,
    };
    const memberIds = getGroupMemberIds(groupId);
    notifyNewGroupMessage(memberIds, me, payload);
    return res.status(201).json(payload);
  }

  let attachmentPath = req.file?.filename ?? null;
  if (req.file) {
    const fullPath = path.join(uploadsDir, req.file.filename);
    try {
      const stat = fs.statSync(fullPath);
      if (stat.size >= MIN_SIZE_TO_COMPRESS) {
        const data = fs.readFileSync(fullPath);
        const compressed = zlib.gzipSync(data);
        fs.writeFileSync(fullPath + '.gz', compressed);
        fs.unlinkSync(fullPath);
        attachmentPath = req.file.filename + '.gz';
      }
    } catch (_) {}
  }
  const attachmentFilename = req.file?.originalname ?? null;
  const attachmentKind = (req.body?.attachment_kind === 'voice' || req.body?.attachment_kind === 'video_note')
    ? req.body.attachment_kind
    : 'file';
  const attachmentDurationSec = req.body?.attachment_duration_sec != null
    ? parseInt(req.body.attachment_duration_sec, 10)
    : null;
  const attachmentEncrypted = req.body?.attachment_encrypted === 'true' || req.body?.attachment_encrypted === true ? 1 : 0;
  const contentToStore = text || (attachmentKind === 'voice' ? 'Голосовое сообщение' : attachmentKind === 'video_note' ? 'Видеокружок' : '(файл)');

  const ins = db.prepare(
    `INSERT INTO group_messages (group_id, sender_id, content, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name)
     VALUES (?, ?, ?, ?, ?, 'text', ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    groupId,
    me,
    contentToStore,
    attachmentPath,
    attachmentFilename,
    attachmentKind,
    attachmentDurationSec,
    attachmentEncrypted,
    Number.isNaN(replyToId) ? null : replyToId,
    isFwd ? 1 : 0,
    fwdFromId,
    fwdFromName,
  );
  const msgId = ins.lastInsertRowid;
  const row = db.prepare(
    'SELECT id, group_id, sender_id, content, created_at, attachment_path, attachment_filename, message_type, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name FROM group_messages WHERE id = ?',
  ).get(msgId);
  const sender = db.prepare('SELECT public_key, display_name, username FROM users WHERE id = ?').get(me);
  const payload = {
    id: row.id,
    group_id: row.group_id,
    sender_id: row.sender_id,
    sender_display_name: sender?.display_name || sender?.username || '?',
    content: row.content,
    created_at: row.created_at,
    is_mine: true,
    attachment_url: row.attachment_path ? `${baseUrl}/uploads/${row.attachment_path}` : null,
    attachment_filename: row.attachment_filename || null,
    message_type: row.message_type || 'text',
    poll_id: null,
    attachment_kind: row.attachment_kind || 'file',
    attachment_duration_sec: row.attachment_duration_sec ?? null,
    attachment_encrypted: !!(row.attachment_encrypted),
    sender_public_key: sender?.public_key ?? null,
    reply_to_id: row.reply_to_id ?? null,
    is_forwarded: !!(row.is_forwarded),
    forward_from_sender_id: row.forward_from_sender_id ?? null,
    forward_from_display_name: row.forward_from_display_name ?? null,
  };
  if (row.reply_to_id) {
    const replyRow = db.prepare('SELECT content, sender_id FROM group_messages WHERE id = ?').get(row.reply_to_id);
    if (replyRow) {
      const replySender = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(replyRow.sender_id);
      payload.reply_to_content = (replyRow.content || '').length > 80 ? (replyRow.content || '').slice(0, 77) + '...' : (replyRow.content || '');
      payload.reply_to_sender_name = replySender?.display_name || replySender?.username || '?';
    }
  }
  const memberIds = getGroupMemberIds(groupId);
  notifyNewGroupMessage(memberIds, me, payload);
  res.status(201).json(payload);
});

// Голос в опросе группы
router.post('/:id/polls/:pollId/vote', (req, res) => {
  const groupId = parseInt(req.params.id, 10);
  const pollId = parseInt(req.params.pollId, 10);
  if (Number.isNaN(groupId) || Number.isNaN(pollId)) return res.status(400).json({ error: 'Некорректный id' });
  const me = req.user.userId;
  if (!isMember(me, groupId)) return res.status(404).json({ error: 'Группа не найдена' });
  const { option_index, option_indexes } = req.body || {};
  const poll = db.prepare('SELECT id, group_message_id, options, multiple FROM group_polls WHERE id = ?').get(pollId);
  if (!poll) return res.status(404).json({ error: 'Опрос не найден' });
  const msg = db.prepare('SELECT group_id FROM group_messages WHERE id = ?').get(poll.group_message_id);
  if (!msg || msg.group_id !== groupId) return res.status(404).json({ error: 'Опрос не найден' });
  const options = JSON.parse(poll.options || '[]');
  const indices = option_indexes != null && Array.isArray(option_indexes)
    ? option_indexes.map((x) => parseInt(x, 10)).filter((i) => !Number.isNaN(i) && i >= 0 && i < options.length)
    : (option_index != null && !Number.isNaN(parseInt(option_index, 10)))
      ? [parseInt(option_index, 10)]
      : [];
  const idx = indices[0];
  if (poll.multiple) {
    if (indices.length === 0) return res.status(400).json({ error: 'Выберите вариант(ы)' });
  } else {
    if (indices.length !== 1 || idx < 0 || idx >= options.length) return res.status(400).json({ error: 'Выберите один вариант' });
  }
  db.prepare('DELETE FROM group_poll_votes WHERE group_poll_id = ? AND user_id = ?').run(pollId, me);
  const insertVote = db.prepare('INSERT INTO group_poll_votes (group_poll_id, user_id, option_index) VALUES (?, ?, ?)');
  if (poll.multiple) {
    for (const i of indices) {
      if (i >= 0 && i < options.length) insertVote.run(pollId, me, i);
    }
  } else {
    insertVote.run(pollId, me, idx);
  }
  const votes = db.prepare('SELECT option_index, user_id FROM group_poll_votes WHERE group_poll_id = ?').all(pollId);
  const counts = options.map((_, i) => votes.filter((v) => v.option_index === i).length);
  const myVotes = votes.filter((v) => v.user_id === me).map((v) => v.option_index);
  res.json({
    poll_id: pollId,
    options: options.map((text, i) => ({ text, votes: counts[i], voted: myVotes.includes(i) })),
  });
});

export default router;
