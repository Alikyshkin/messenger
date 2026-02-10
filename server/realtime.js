// WebSocket clients: userId -> Set<WebSocket>
export const clients = new Map();

export function broadcastToUser(userId, data) {
  const set = clients.get(userId);
  if (!set) return;
  const msg = JSON.stringify(data);
  set.forEach(ws => {
    if (ws.readyState === 1) ws.send(msg);
  });
}

export function notifyNewMessage(message) {
  const forReceiver = { ...message, is_mine: false };
  broadcastToUser(message.receiver_id, { type: 'new_message', message: forReceiver });
}

/** Уведомить всех участников группы о новом сообщении (кроме отправителя — он получит от API). */
export function notifyNewGroupMessage(memberUserIds, senderId, message) {
  const forOthers = { ...message, is_mine: false };
  memberUserIds.forEach((userId) => {
    if (Number(userId) !== Number(senderId)) {
      broadcastToUser(userId, { type: 'new_group_message', group_id: message.group_id, message: forOthers });
    }
  });
}

/** Реакция на личное сообщение: уведомить обоих участников чата. */
export function notifyReaction(messageId, senderId, receiverId, reactions) {
  const payload = { type: 'reaction', message_id: messageId, peer_id: null, reactions };
  broadcastToUser(senderId, { ...payload, peer_id: receiverId });
  broadcastToUser(receiverId, { ...payload, peer_id: senderId });
}

/** Реакция на сообщение в группе: уведомить всех участников. */
export function notifyGroupReaction(memberUserIds, groupId, messageId, reactions) {
  const payload = { type: 'group_reaction', group_id: groupId, message_id: messageId, reactions };
  memberUserIds.forEach((userId) => broadcastToUser(userId, payload));
}
