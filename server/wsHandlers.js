/**
 * Обработчики WebSocket-сообщений. Вынесены из index.js для разделения ответственности.
 */
import db from './db.js';
import { clients, broadcastToUser, broadcastTyping, broadcastGroupTyping } from './realtime.js';
import { isCommunicationBlocked } from './utils/blocked.js';
import { canCall } from './utils/privacy.js';
import { log } from './utils/logger.js';

/**
 * Обрабатывает входящее WebSocket-сообщение.
 * @param {Buffer|string} raw - сырые данные сообщения
 * @param {{ userId: number; req: import('http').IncomingMessage }} ctx - контекст (userId, req)
 */
export async function handleWsMessage(raw, ctx) {
  const { userId, req } = ctx;
  try {
    const data = JSON.parse(raw.toString());

    if (!data.type || typeof data.type !== 'string') {
      log.warn('Invalid WebSocket message: missing or invalid type', { userId });
      return;
    }

    if (data.type === 'call_signal') {
      await handleCallSignal(data, userId, req);
      return;
    }

    if (data.type === 'typing') {
      handleTyping(data, userId);
      return;
    }

    if (data.type === 'group_typing') {
      handleGroupTyping(data, userId);
      return;
    }

    if (data.type === 'group_call_signal') {
      handleGroupCallSignal(data, userId);
    }
  } catch (_) {
    // Игнорируем ошибки парсинга/обработки отдельного сообщения
  }
}

async function handleCallSignal(data, userId, req) {
  if (data.toUserId == null || typeof data.toUserId !== 'number') {
    log.warn('Invalid call_signal: missing or invalid toUserId', { userId });
    return;
  }
  if (!data.signal || typeof data.signal !== 'string') {
    log.warn('Invalid call_signal: missing or invalid signal', { userId });
    return;
  }

  const toId = Number(data.toUserId);
  if (!Number.isInteger(toId) || toId <= 0 || toId === userId) {
    log.warn('Invalid call_signal: invalid toUserId', { userId, toId });
    return;
  }

  const groupId = data.groupId != null ? Number(data.groupId) : null;
  if (groupId != null && (!Number.isInteger(groupId) || groupId <= 0)) {
    log.warn('Invalid call_signal: invalid groupId', { userId, groupId });
    return;
  }

  if (groupId == null) {
    if (isCommunicationBlocked(userId, toId)) {
      log.warn('call_signal blocked: users have blocked each other', { userId, toId });
      return;
    }
    if (!canCall(userId, toId)) {
      log.warn('call_signal blocked: callee privacy settings', { userId, toId });
      return;
    }
  }

  const set = clients.get(toId);
  const n = set ? set.size : 0;
  log.ws('call_signal', { fromUserId: userId, toUserId: toId, connections: n });

  if (data.signal === 'reject') {
    try {
      const senderExists = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
      const receiverExists = db.prepare('SELECT id FROM users WHERE id = ?').get(toId);
      if (!senderExists || !receiverExists) {
        log.warn('Cannot create missed call message: user not found', { senderId: userId, receiverId: toId });
        return;
      }

      const { syncMessagesFTS } = await import('./utils/ftsSync.js');
      const senderUser = db.prepare('SELECT public_key FROM users WHERE id = ?').get(userId);
      const result = db.prepare(
        `INSERT INTO messages (sender_id, receiver_id, content, message_type, sender_public_key) VALUES (?, ?, ?, ?, ?)`
      ).run(userId, toId, 'Пропущенный звонок', 'missed_call', senderUser?.public_key ?? null);
      const msgId = result.lastInsertRowid;
      syncMessagesFTS(msgId);
      const row = db.prepare(
        'SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, attachment_filename, message_type, poll_id, attachment_kind, attachment_duration_sec, attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id, forward_from_display_name, sender_public_key FROM messages WHERE id = ?'
      ).get(msgId);

      if (!row) {
        log.error('Failed to retrieve created missed call message', { msgId });
        return;
      }

      const sender = db.prepare('SELECT public_key, display_name, username FROM users WHERE id = ?').get(row.sender_id);
      const senderKey = row.sender_public_key ?? sender?.public_key;
      const proto = req.headers['x-forwarded-proto'] || (req.socket?.encrypted ? 'https' : 'http');
      const host = req.headers.host || 'localhost:3000';
      const baseUrl = `${proto}://${host}`;
      const payload = {
        id: row.id,
        sender_id: row.sender_id,
        receiver_id: row.receiver_id,
        content: row.content,
        created_at: row.created_at,
        read_at: row.read_at,
        is_mine: false,
        attachment_url: null,
        attachment_filename: null,
        message_type: row.message_type || 'text',
        poll_id: null,
        attachment_kind: 'file',
        attachment_duration_sec: null,
        attachment_encrypted: false,
        sender_public_key: senderKey ?? null,
        sender_display_name: sender?.display_name || sender?.username || '?',
        reply_to_id: null,
        is_forwarded: false,
        forward_from_sender_id: null,
        forward_from_display_name: null,
      };
      broadcastToUser(payload.sender_id, { type: 'new_message', ...payload, is_mine: true });
      broadcastToUser(payload.receiver_id, { type: 'new_message', ...payload, is_mine: false });
    } catch (e) {
      log.error('Ошибка при создании сообщения о пропущенном звонке', e);
    }
  }

  const recipientExists = db.prepare('SELECT id FROM users WHERE id = ?').get(toId);
  if (!recipientExists) {
    log.warn('Cannot send call signal: recipient not found', { toId, fromUserId: userId });
    return;
  }

  let isVideoCall = true;
  if (data.isVideoCall !== undefined && data.isVideoCall !== null) {
    isVideoCall = Boolean(data.isVideoCall);
  }

  const signalPayload = {
    type: 'call_signal',
    fromUserId: userId,
    signal: data.signal,
    payload: data.payload ?? null,
    isVideoCall,
  };
  if (groupId != null) {
    signalPayload.groupId = groupId;
  }
  broadcastToUser(toId, signalPayload);
}

function handleTyping(data, userId) {
  const toUserId = data.toUserId != null ? Number(data.toUserId) : null;
  if (toUserId && Number.isInteger(toUserId) && toUserId > 0 && toUserId !== userId) {
    if (!isCommunicationBlocked(userId, toUserId)) {
      const user = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(userId);
      const displayName = user?.display_name || user?.username || 'User';
      broadcastTyping(toUserId, userId, displayName);
    }
  }
}

function handleGroupTyping(data, userId) {
  const groupId = data.groupId != null ? Number(data.groupId) : null;
  if (groupId && Number.isInteger(groupId) && groupId > 0) {
    const isMember = db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, userId);
    if (isMember) {
      const members = db.prepare('SELECT user_id FROM group_members WHERE group_id = ?').all(groupId);
      const user = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(userId);
      const displayName = user?.display_name || user?.username || 'User';
      broadcastGroupTyping(groupId, userId, displayName, members.map(m => m.user_id));
    }
  }
}

function handleGroupCallSignal(data, userId) {
  if (!data.groupId || typeof data.groupId !== 'number') {
    log.warn('Invalid group_call_signal: missing or invalid groupId', { userId });
    return;
  }
  if (!data.signal || typeof data.signal !== 'string') {
    log.warn('Invalid group_call_signal: missing or invalid signal', { userId });
    return;
  }

  const groupId = Number(data.groupId);
  if (!Number.isInteger(groupId) || groupId <= 0) {
    log.warn('Invalid group_call_signal: invalid groupId', { userId, groupId });
    return;
  }

  const isMember = db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?').get(groupId, userId);
  if (!isMember) {
    log.warn('Invalid group_call_signal: user is not a member of the group', { userId, groupId });
    return;
  }

  const members = db.prepare('SELECT user_id FROM group_members WHERE group_id = ? AND user_id != ?').all(groupId, userId);
  const memberIds = members.map(m => m.user_id);

  log.ws('group_call_signal', { fromUserId: userId, groupId, signal: data.signal, members: memberIds.length });

  memberIds.forEach(memberId => {
    broadcastToUser(memberId, {
      type: 'call_signal',
      fromUserId: userId,
      signal: data.signal,
      payload: data.payload ?? null,
      isVideoCall: data.isVideoCall ?? true,
      groupId,
    });
  });
}
