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
