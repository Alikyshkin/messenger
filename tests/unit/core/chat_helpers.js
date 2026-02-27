/**
 * Хелперы для тестов чатов и сообщений.
 */
import { fetchJson, authHeaders } from '../helpers.js';

/**
 * Отправляет текстовое сообщение.
 */
export async function sendMessage(baseUrl, token, { receiverId, content, replyToId } = {}) {
  const body = { receiver_id: receiverId, content };
  if (replyToId != null) body.reply_to_id = replyToId;
  return fetchJson(baseUrl, '/messages', {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify(body),
  });
}

/**
 * Получает сообщения с пользователем (peer).
 */
export async function getMessages(baseUrl, token, peerId) {
  return fetchJson(baseUrl, `/messages/${peerId}`, {
    headers: authHeaders(token),
  });
}

/**
 * Отмечает сообщения как прочитанные.
 */
export async function markAsRead(baseUrl, token, peerId) {
  const res = await fetch(baseUrl + `/messages/${peerId}/read`, {
    method: 'PATCH',
    headers: authHeaders(token),
  });
  return { status: res.status };
}
