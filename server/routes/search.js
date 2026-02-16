import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { decryptIfLegacy } from '../cipher.js';
import { validatePagination } from '../middleware/pagination.js';
import { SEARCH_CONFIG } from '../config/constants.js';
import { getUsersByIds } from '../utils/queryOptimizer.js';

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

const ALLOWED_SEARCH_TYPES = new Set(['text', 'image', 'video', 'file', 'voice', 'video_note', 'poll', 'link', 'all']);

/**
 * Поиск по сообщениям в личных чатах
 * GET /search/messages?q=текст&peerId=123&type=image|video|file|voice|text|all&senderId=456&limit=50&offset=0
 */
router.get('/messages', validatePagination, (req, res) => {
  const { q } = req.query;
  const peerId = req.query.peerId ? parseInt(req.query.peerId, 10) : null;
  const senderId = req.query.senderId ? parseInt(req.query.senderId, 10) : null;
  const typeFilter = req.query.type && ALLOWED_SEARCH_TYPES.has(req.query.type) ? req.query.type : 'all';
  const { limit = 50, offset = 0 } = req.pagination;
  const me = req.user.userId;
  
  if (!q || typeof q !== 'string' || q.trim().length < SEARCH_CONFIG.MIN_QUERY_LENGTH) {
    return res.json({ data: [], pagination: { total: 0, limit, offset } });
  }
  
  const query = q.trim();
  const baseUrl = getBaseUrl(req);
  
  try {
    let sql = `
      SELECT m.id, m.sender_id, m.receiver_id, m.content, m.created_at, m.attachment_path, 
             m.attachment_filename, m.message_type, m.attachment_kind, m.attachment_duration_sec,
             m.attachment_encrypted, m.reply_to_id, m.is_forwarded, m.forward_from_sender_id,
             m.forward_from_display_name
      FROM messages m
      JOIN messages_fts fts ON m.id = fts.rowid
      WHERE (m.sender_id = ? OR m.receiver_id = ?)
        AND (m.sender_id = ? OR m.receiver_id = ?)
        AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = ? AND b.blocked_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END)
        AND messages_fts MATCH ?
    `;
    
    const params = [me, me];
    if (peerId) {
      params.push(peerId, peerId);
      sql = sql.replace('(m.sender_id = ? OR m.receiver_id = ?)', '(m.sender_id = ? AND m.receiver_id = ?) OR (m.sender_id = ? AND m.receiver_id = ?)');
    } else {
      params.push(me, me);
    }
    params.push(me, me, `"${query}"`);

    if (senderId && Number.isInteger(senderId)) {
      sql += ' AND m.sender_id = ?';
      params.push(senderId);
    }
    if (typeFilter !== 'all') {
      if (typeFilter === 'text') {
        sql += ' AND (m.message_type = ? OR m.message_type IS NULL) AND m.attachment_path IS NULL';
        params.push('text');
      } else if (typeFilter === 'image') {
        sql += ' AND m.attachment_path IS NOT NULL AND (LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ?)';
        params.push('%.jpg', '%.jpeg', '%.png', '%.gif', '%.webp');
      } else if (typeFilter === 'video') {
        sql += ' AND (m.attachment_kind = ? OR m.message_type = ? OR LOWER(m.attachment_filename) LIKE ?)';
        params.push('video', 'video_note', '%.mp4');
      } else if (typeFilter === 'file') {
        sql += ' AND m.attachment_path IS NOT NULL AND m.attachment_kind = ?';
        params.push('file');
      } else if (typeFilter === 'voice') {
        sql += ' AND m.attachment_kind = ?';
        params.push('voice');
      } else if (typeFilter === 'video_note') {
        sql += ' AND m.attachment_kind = ?';
        params.push('video_note');
      } else if (typeFilter === 'poll') {
        sql += ' AND m.message_type = ?';
        params.push('poll');
      } else if (typeFilter === 'link') {
        sql += ' AND m.content LIKE ?';
        params.push('%http%');
      }
    }
    
    sql += ' ORDER BY m.created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const rows = db.prepare(sql).all(...params);
    
    // Подсчитываем общее количество результатов
    let countSql = `
      SELECT COUNT(*) as cnt
      FROM messages m
      JOIN messages_fts fts ON m.id = fts.rowid
      WHERE (m.sender_id = ? OR m.receiver_id = ?)
        AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = ? AND b.blocked_id = CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END)
        AND messages_fts MATCH ?
    `;
    const countParams = [me, me, me, me, `"${query}"`];
    if (peerId) {
      countSql = countSql.replace('(m.sender_id = ? OR m.receiver_id = ?)', '(m.sender_id = ? AND m.receiver_id = ?) OR (m.sender_id = ? AND m.receiver_id = ?)');
      countParams.splice(2, 0, peerId, peerId);
    }
    if (senderId && Number.isInteger(senderId)) {
      countSql += ' AND m.sender_id = ?';
      countParams.push(senderId);
    }
    if (typeFilter !== 'all') {
      if (typeFilter === 'text') {
        countSql += ' AND (m.message_type = ? OR m.message_type IS NULL) AND m.attachment_path IS NULL';
        countParams.push('text');
      } else if (typeFilter === 'image') {
        countSql += ' AND m.attachment_path IS NOT NULL AND (LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ?)';
        countParams.push('%.jpg', '%.jpeg', '%.png', '%.gif', '%.webp');
      } else if (typeFilter === 'video') {
        countSql += ' AND (m.attachment_kind = ? OR m.message_type = ? OR LOWER(m.attachment_filename) LIKE ?)';
        countParams.push('video', 'video_note', '%.mp4');
      } else if (typeFilter === 'file') {
        countSql += ' AND m.attachment_path IS NOT NULL AND m.attachment_kind = ?';
        countParams.push('file');
      } else if (typeFilter === 'voice') {
        countSql += ' AND m.attachment_kind = ?';
        countParams.push('voice');
      } else if (typeFilter === 'video_note') {
        countSql += ' AND m.attachment_kind = ?';
        countParams.push('video_note');
      } else if (typeFilter === 'poll') {
        countSql += ' AND m.message_type = ?';
        countParams.push('poll');
      } else if (typeFilter === 'link') {
        countSql += ' AND m.content LIKE ?';
        countParams.push('%http%');
      }
    }
    const total = db.prepare(countSql).get(...countParams)?.cnt || 0;
    
    // Оптимизация: получаем всех пользователей одним запросом
    const userIds = new Set();
    rows.forEach(r => {
      userIds.add(r.sender_id);
      userIds.add(r.receiver_id);
    });
    const usersMap = getUsersByIds([...userIds]);
    
    const results = rows.map(r => {
      const sender = usersMap.get(r.sender_id);
      const peerId = r.sender_id === me ? r.receiver_id : r.sender_id;
      const peer = usersMap.get(peerId);
      
      return {
        id: r.id,
        sender_id: r.sender_id,
        receiver_id: r.receiver_id,
        peer: {
          id: peerId,
          display_name: peer?.display_name || peer?.username || '?',
        },
        content: decryptIfLegacy(r.content),
        created_at: r.created_at,
        is_mine: r.sender_id === me,
        attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
        attachment_filename: r.attachment_filename || null,
        message_type: r.message_type || 'text',
        attachment_kind: r.attachment_kind || 'file',
        attachment_duration_sec: r.attachment_duration_sec ?? null,
        attachment_encrypted: !!(r.attachment_encrypted),
        sender_public_key: sender?.public_key ?? null,
        reply_to_id: r.reply_to_id ?? null,
        is_forwarded: !!(r.is_forwarded),
        forward_from_sender_id: r.forward_from_sender_id ?? null,
        forward_from_display_name: r.forward_from_display_name ?? null,
      };
    });
    
    res.json({
      data: results,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    });
  } catch (error) {
    // Если FTS5 не поддерживается или таблица не создана, возвращаем простой поиск
    let sql = `
      SELECT id, sender_id, receiver_id, content, created_at, attachment_path, 
             attachment_filename, message_type, attachment_kind, attachment_duration_sec,
             attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id,
             forward_from_display_name
      FROM messages
      WHERE (sender_id = ? OR receiver_id = ?)
        AND content LIKE ?
    `;
    
    const params = [me, me, `%${query}%`];
    if (peerId) {
      sql = sql.replace('(sender_id = ? OR receiver_id = ?)', '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)');
      params.splice(2, 0, peerId, peerId);
    }
    
    sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const rows = db.prepare(sql).all(...params);
    const total = db.prepare(`
      SELECT COUNT(*) as cnt FROM messages
      WHERE (sender_id = ? OR receiver_id = ?) AND content LIKE ?
    `).get(me, me, `%${query}%`)?.cnt || 0;
    
    // Оптимизация: получаем всех пользователей одним запросом
    const userIds = new Set();
    rows.forEach(r => {
      userIds.add(r.sender_id);
      userIds.add(r.receiver_id);
    });
    const usersMap = getUsersByIds([...userIds]);
    
    const results = rows.map(r => {
      const sender = usersMap.get(r.sender_id);
      const peerId = r.sender_id === me ? r.receiver_id : r.sender_id;
      const peer = usersMap.get(peerId);
      
      return {
        id: r.id,
        sender_id: r.sender_id,
        receiver_id: r.receiver_id,
        peer: {
          id: peerId,
          display_name: peer?.display_name || peer?.username || '?',
        },
        content: decryptIfLegacy(r.content),
        created_at: r.created_at,
        is_mine: r.sender_id === me,
        attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
        attachment_filename: r.attachment_filename || null,
        message_type: r.message_type || 'text',
        attachment_kind: r.attachment_kind || 'file',
        attachment_duration_sec: r.attachment_duration_sec ?? null,
        attachment_encrypted: !!(r.attachment_encrypted),
        sender_public_key: sender?.public_key ?? null,
        reply_to_id: r.reply_to_id ?? null,
        is_forwarded: !!(r.is_forwarded),
        forward_from_sender_id: r.forward_from_sender_id ?? null,
        forward_from_display_name: r.forward_from_display_name ?? null,
      };
    });
    
    res.json({
      data: results,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    });
  }
});

/**
 * Поиск по сообщениям в группах
 * GET /search/group-messages?q=текст&groupId=123&type=image|video|file|voice|text|all&senderId=456&limit=50&offset=0
 */
router.get('/group-messages', validatePagination, (req, res) => {
  const { q } = req.query;
  const groupId = req.query.groupId ? parseInt(req.query.groupId, 10) : null;
  const senderId = req.query.senderId ? parseInt(req.query.senderId, 10) : null;
  const typeFilter = req.query.type && ALLOWED_SEARCH_TYPES.has(req.query.type) ? req.query.type : 'all';
  const { limit = 50, offset = 0 } = req.pagination;
  const me = req.user.userId;
  
  if (!q || typeof q !== 'string' || q.trim().length < SEARCH_CONFIG.MIN_QUERY_LENGTH) {
    return res.json({ data: [], pagination: { total: 0, limit, offset } });
  }
  
  if (groupId) {
    // Проверяем, что пользователь является участником группы
    const isMember = db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, me);
    if (!isMember) {
      return res.status(403).json({ error: 'Нет доступа к группе' });
    }
  }
  
  const query = q.trim();
  const baseUrl = getBaseUrl(req);
  
  try {
    let sql = `
      SELECT m.id, m.group_id, m.sender_id, m.content, m.created_at, m.attachment_path,
             m.attachment_filename, m.message_type, m.attachment_kind, m.attachment_duration_sec,
             m.attachment_encrypted, m.reply_to_id, m.is_forwarded, m.forward_from_sender_id,
             m.forward_from_display_name
      FROM group_messages m
      JOIN group_messages_fts fts ON m.id = fts.rowid
      WHERE m.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
        AND group_messages_fts MATCH ?
    `;
    
    const params = [me, `"${query}"`];
    if (groupId) {
      sql = sql.replace('m.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)', 'm.group_id = ?');
      params[0] = groupId;
    }
    if (senderId && Number.isInteger(senderId)) {
      sql += ' AND m.sender_id = ?';
      params.push(senderId);
    }
    if (typeFilter !== 'all') {
      if (typeFilter === 'text') {
        sql += ' AND (m.message_type = ? OR m.message_type IS NULL) AND m.attachment_path IS NULL';
        params.push('text');
      } else if (typeFilter === 'image') {
        sql += ' AND m.attachment_path IS NOT NULL AND (LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ?)';
        params.push('%.jpg', '%.jpeg', '%.png', '%.gif', '%.webp');
      } else if (typeFilter === 'video') {
        sql += ' AND (m.attachment_kind = ? OR m.message_type = ? OR LOWER(m.attachment_filename) LIKE ?)';
        params.push('video', 'video_note', '%.mp4');
      } else if (typeFilter === 'file') {
        sql += ' AND m.attachment_path IS NOT NULL AND m.attachment_kind = ?';
        params.push('file');
      } else if (typeFilter === 'voice') {
        sql += ' AND m.attachment_kind = ?';
        params.push('voice');
      } else if (typeFilter === 'video_note') {
        sql += ' AND m.attachment_kind = ?';
        params.push('video_note');
      } else if (typeFilter === 'poll') {
        sql += ' AND m.message_type = ?';
        params.push('poll');
      } else if (typeFilter === 'link') {
        sql += ' AND m.content LIKE ?';
        params.push('%http%');
      }
    }
    
    sql += ' ORDER BY m.created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const rows = db.prepare(sql).all(...params);
    
    // Подсчитываем общее количество результатов
    let countSql = `
      SELECT COUNT(*) as cnt
      FROM group_messages m
      JOIN group_messages_fts fts ON m.id = fts.rowid
      WHERE m.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
        AND group_messages_fts MATCH ?
    `;
    const countParams = [me, `"${query}"`];
    if (groupId) {
      countSql = countSql.replace('m.group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)', 'm.group_id = ?');
      countParams[0] = groupId;
    }
    if (senderId && Number.isInteger(senderId)) {
      countSql += ' AND m.sender_id = ?';
      countParams.push(senderId);
    }
    if (typeFilter !== 'all') {
      if (typeFilter === 'text') {
        countSql += ' AND (m.message_type = ? OR m.message_type IS NULL) AND m.attachment_path IS NULL';
        countParams.push('text');
      } else if (typeFilter === 'image') {
        countSql += ' AND m.attachment_path IS NOT NULL AND (LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ? OR LOWER(m.attachment_filename) LIKE ?)';
        countParams.push('%.jpg', '%.jpeg', '%.png', '%.gif', '%.webp');
      } else if (typeFilter === 'video') {
        countSql += ' AND (m.attachment_kind = ? OR m.message_type = ? OR LOWER(m.attachment_filename) LIKE ?)';
        countParams.push('video', 'video_note', '%.mp4');
      } else if (typeFilter === 'file') {
        countSql += ' AND m.attachment_path IS NOT NULL AND m.attachment_kind = ?';
        countParams.push('file');
      } else if (typeFilter === 'voice') {
        countSql += ' AND m.attachment_kind = ?';
        countParams.push('voice');
      } else if (typeFilter === 'video_note') {
        countSql += ' AND m.attachment_kind = ?';
        countParams.push('video_note');
      } else if (typeFilter === 'poll') {
        countSql += ' AND m.message_type = ?';
        countParams.push('poll');
      } else if (typeFilter === 'link') {
        countSql += ' AND m.content LIKE ?';
        countParams.push('%http%');
      }
    }
    const total = db.prepare(countSql).get(...countParams)?.cnt || 0;
    
    // Оптимизация: получаем всех отправителей одним запросом
    const senderIds = [...new Set(rows.map(r => r.sender_id))];
    const sendersMap = getUsersByIds(senderIds);
    
    // Оптимизация: получаем все группы одним запросом
    const groupIds = [...new Set(rows.map(r => r.group_id))];
    const groupPlaceholders = groupIds.map(() => '?').join(',');
    const groupsRows = db.prepare(`SELECT id, name FROM groups WHERE id IN (${groupPlaceholders})`).all(...groupIds);
    const groupsMap = new Map(groupsRows.map(g => [g.id, g]));
    
    const results = rows.map(r => {
      const sender = sendersMap.get(r.sender_id);
      const group = groupsMap.get(r.group_id);
      
      return {
        id: r.id,
        group_id: r.group_id,
        group_name: group?.name || '?',
        sender_id: r.sender_id,
        sender_display_name: sender?.display_name || sender?.username || '?',
        content: decryptIfLegacy(r.content),
        created_at: r.created_at,
        is_mine: r.sender_id === me,
        attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
        attachment_filename: r.attachment_filename || null,
        message_type: r.message_type || 'text',
        attachment_kind: r.attachment_kind || 'file',
        attachment_duration_sec: r.attachment_duration_sec ?? null,
        attachment_encrypted: !!(r.attachment_encrypted),
        sender_public_key: sender?.public_key ?? null,
        reply_to_id: r.reply_to_id ?? null,
        is_forwarded: !!(r.is_forwarded),
        forward_from_sender_id: r.forward_from_sender_id ?? null,
        forward_from_display_name: r.forward_from_display_name ?? null,
      };
    });
    
    res.json({
      data: results,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    });
  } catch (error) {
    // Fallback на простой поиск
    let sql = `
      SELECT id, group_id, sender_id, content, created_at, attachment_path,
             attachment_filename, message_type, attachment_kind, attachment_duration_sec,
             attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id,
             forward_from_display_name
      FROM group_messages
      WHERE group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)
        AND content LIKE ?
    `;
    
    const params = [me, `%${query}%`];
    if (groupId) {
      sql = sql.replace('group_id IN (SELECT group_id FROM group_members WHERE user_id = ?)', 'group_id = ?');
      params[0] = groupId;
    }
    
    sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);
    
    const rows = db.prepare(sql).all(...params);
    const total = db.prepare(`
      SELECT COUNT(*) as cnt FROM group_messages
      WHERE group_id IN (SELECT group_id FROM group_members WHERE user_id = ?) AND content LIKE ?
    `).get(me, `%${query}%`)?.cnt || 0;
    
    // Оптимизация: получаем всех отправителей одним запросом
    const senderIds = [...new Set(rows.map(r => r.sender_id))];
    const sendersMap = getUsersByIds(senderIds);
    
    // Оптимизация: получаем все группы одним запросом
    const groupIds = [...new Set(rows.map(r => r.group_id))];
    const groupPlaceholders = groupIds.map(() => '?').join(',');
    const groupsRows = db.prepare(`SELECT id, name FROM groups WHERE id IN (${groupPlaceholders})`).all(...groupIds);
    const groupsMap = new Map(groupsRows.map(g => [g.id, g]));
    
    const results = rows.map(r => {
      const sender = sendersMap.get(r.sender_id);
      const group = groupsMap.get(r.group_id);
      
      return {
        id: r.id,
        group_id: r.group_id,
        group_name: group?.name || '?',
        sender_id: r.sender_id,
        sender_display_name: sender?.display_name || sender?.username || '?',
        content: decryptIfLegacy(r.content),
        created_at: r.created_at,
        is_mine: r.sender_id === me,
        attachment_url: r.attachment_path ? `${baseUrl}/uploads/${r.attachment_path}` : null,
        attachment_filename: r.attachment_filename || null,
        message_type: r.message_type || 'text',
        attachment_kind: r.attachment_kind || 'file',
        attachment_duration_sec: r.attachment_duration_sec ?? null,
        attachment_encrypted: !!(r.attachment_encrypted),
        sender_public_key: sender?.public_key ?? null,
        reply_to_id: r.reply_to_id ?? null,
        is_forwarded: !!(r.is_forwarded),
        forward_from_sender_id: r.forward_from_sender_id ?? null,
        forward_from_display_name: r.forward_from_display_name ?? null,
      };
    });
    
    res.json({
      data: results,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + limit < total,
      },
    });
  }
});

export default router;
