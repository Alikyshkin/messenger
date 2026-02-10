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
  broadcastToUser(message.receiver_id, { type: 'new_message', message });
}
