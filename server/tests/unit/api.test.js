/**
 * Тесты users, messages, health. Запуск: npm test.
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { server } from '../../index.js';
import { fetchJson, register, login, authHeaders } from '../helpers.js';

let baseUrl;
let token1;
let token2;
let userId1;
let userId2;

before(async () => {
  await new Promise((res) => {
    server.listen(0, '127.0.0.1', () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      res();
    });
  });
  const r1 = await register(baseUrl, { username: 'apiuser1', password: 'Str0ngP@ss!' });
  const r2 = await register(baseUrl, { username: 'apiuser2', password: 'Str0ngP@ss!' });
  assert.strictEqual(r1.status, 201, 'register user1: ' + JSON.stringify(r1.data));
  assert.strictEqual(r2.status, 201, 'register user2: ' + JSON.stringify(r2.data));
  token1 = r1.data.token;
  token2 = r2.data.token;
  userId1 = r1.data.user.id;
  userId2 = r2.data.user.id;

  // Устанавливаем взаимные контакты (заявки в друзья + принятие)
  const req1 = await fetchJson(baseUrl, '/contacts', {
    method: 'POST',
    headers: authHeaders(token1),
    body: JSON.stringify({ username: 'apiuser2' }),
  });
  const req2 = await fetchJson(baseUrl, '/contacts', {
    method: 'POST',
    headers: authHeaders(token2),
    body: JSON.stringify({ username: 'apiuser1' }),
  });
  // Принимаем заявки (req1 -> incoming для user2, req2 -> incoming для user1)
  const incoming2 = await fetchJson(baseUrl, '/contacts/requests/incoming', {
    headers: authHeaders(token2),
  });
  for (const r of incoming2.data) {
    await fetchJson(baseUrl, `/contacts/requests/${r.id}/accept`, {
      method: 'POST',
      headers: authHeaders(token2),
    });
  }
  const incoming1 = await fetchJson(baseUrl, '/contacts/requests/incoming', {
    headers: authHeaders(token1),
  });
  for (const r of incoming1.data) {
    await fetchJson(baseUrl, `/contacts/requests/${r.id}/accept`, {
      method: 'POST',
      headers: authHeaders(token1),
    });
  }
});

after(() => server.close());

describe('Health', () => {
  it('GET /health returns ok', async () => {
    const { status, data } = await fetchJson(baseUrl, '/health');
    assert.strictEqual(status, 200);
    assert.strictEqual(data.status, 'healthy');
  });
});

describe('Users', () => {
  it('GET /users/me — возвращает профиль по токену', async () => {
    const { status, data } = await fetchJson(baseUrl, '/users/me', {
      headers: authHeaders(token1),
    });
    assert.strictEqual(status, 200);
    assert.strictEqual(data.username, 'apiuser1');
    assert.strictEqual(data.id, userId1);
  });

  it('GET /users/me — 401 без токена', async () => {
    const res = await fetch(baseUrl + '/users/me');
    assert.strictEqual(res.status, 401);
  });

  it('PATCH /users/me — обновляет display_name и bio', async () => {
    const { status, data } = await fetchJson(baseUrl, '/users/me', {
      method: 'PATCH',
      headers: authHeaders(token1),
      body: JSON.stringify({ display_name: 'Alice', bio: 'Hello world' }),
    });
    assert.strictEqual(status, 200);
    assert.strictEqual(data.display_name, 'Alice');
    assert.strictEqual(data.bio, 'Hello world');
  });
});

describe('Messages', () => {
  it('GET /messages/:peerId — требует авторизации', async () => {
    const res = await fetch(baseUrl + '/messages/' + userId2);
    assert.strictEqual(res.status, 401);
  });

  it('GET /messages/:peerId — пустой список между двумя пользователями', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages/' + userId2, {
      headers: authHeaders(token1),
    });
    assert.strictEqual(status, 200);
    const list = data?.data ?? data;
    assert.ok(Array.isArray(list));
    assert.strictEqual(list.length, 0);
  });

  it('POST /messages — отправка текста', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: authHeaders(token1),
      body: JSON.stringify({ receiver_id: userId2, content: 'Hello from 1' }),
    });
    assert.strictEqual(status, 201);
    assert.strictEqual(data.content, 'Hello from 1');
    assert.strictEqual(data.sender_id, userId1);
    assert.strictEqual(data.receiver_id, userId2);
  });

  it('GET /messages/:peerId — возвращает сообщения после отправки', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages/' + userId2, {
      headers: authHeaders(token1),
    });
    assert.strictEqual(status, 200);
    const list = data?.data ?? data;
    assert.ok(list.length >= 1);
    const msg = list.find((m) => m.content === 'Hello from 1');
    assert.ok(msg);
    assert.strictEqual(msg.is_mine, true);
  });

  it('GET /messages/:peerId — сообщения содержат поле reactions (массив)', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages/' + userId2, {
      headers: authHeaders(token1),
    });
    assert.strictEqual(status, 200);
    const list = data?.data ?? data;
    assert.ok(Array.isArray(list));
    for (const msg of list) {
      assert.ok(Array.isArray(msg.reactions), 'message should have reactions array');
    }
  });

  it('POST /messages/:messageId/reaction — ставит реакцию и возвращает reactions', async () => {
    const { data: raw } = await fetchJson(baseUrl, '/messages/' + userId2, {
      headers: authHeaders(token1),
    });
    const list = raw?.data ?? raw;
    const firstMsg = list.find((m) => m.content === 'Hello from 1');
    assert.ok(firstMsg, 'need at least one message');
    const messageId = firstMsg.id;
    const { status, data } = await fetchJson(baseUrl, '/messages/' + messageId + '/reaction', {
      method: 'POST',
      headers: authHeaders(token2),
      body: JSON.stringify({ emoji: '👍' }),
    });
    assert.strictEqual(status, 200);
    assert.ok(Array.isArray(data.reactions));
    const thumbsUp = data.reactions.find((r) => r.emoji === '👍');
    assert.ok(thumbsUp);
    assert.ok(Array.isArray(thumbsUp.user_ids));
    assert.strictEqual(thumbsUp.user_ids.includes(userId2), true);
  });

  it('POST /messages/:messageId/reaction — повторная та же эмодзи снимает реакцию', async () => {
    const { data: raw } = await fetchJson(baseUrl, '/messages/' + userId1, {
      headers: authHeaders(token2),
    });
    const list = raw?.data ?? raw;
    const msg = list.find((m) => m.content === 'Hello from 1');
    assert.ok(msg);
    await fetchJson(baseUrl, '/messages/' + msg.id + '/reaction', {
      method: 'POST',
      headers: authHeaders(token2),
      body: JSON.stringify({ emoji: '❤️' }),
    });
    const { data: after } = await fetchJson(baseUrl, '/messages/' + msg.id + '/reaction', {
      method: 'POST',
      headers: authHeaders(token2),
      body: JSON.stringify({ emoji: '❤️' }),
    });
    const heart = after.reactions.find((r) => r.emoji === '❤️');
    assert.ok(!heart || heart.user_ids.length === 0, 'same emoji again should remove reaction');
  });

  it('POST /messages/:messageId/reaction — 400 на недопустимую эмодзи', async () => {
    const { data: raw } = await fetchJson(baseUrl, '/messages/' + userId2, {
      headers: authHeaders(token1),
    });
    const list = raw?.data ?? raw;
    const messageId = list[0].id;
    const res = await fetch(baseUrl + '/messages/' + messageId + '/reaction', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders(token1) },
      body: JSON.stringify({ emoji: 'invalid' }),
    });
    assert.strictEqual(res.status, 400);
  });

  it('GET /messages/:peerId — поддерживает пагинацию (limit)', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages/' + userId2 + '?limit=1', {
      headers: authHeaders(token1),
    });
    assert.strictEqual(status, 200);
    const list = data?.data ?? data;
    const pagination = data?.pagination ?? {};
    assert.ok(Array.isArray(list));
    assert.ok(list.length <= 1);
    if (pagination.limit !== undefined) assert.strictEqual(pagination.limit, 1);
  });

  it('DELETE /messages/:messageId — удаляет сообщение и возвращает 204', async () => {
    const { data: sendRes } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: authHeaders(token1),
      body: JSON.stringify({ receiver_id: userId2, content: 'To delete' }),
    });
    const messageId = sendRes.id;
    const res = await fetch(baseUrl + '/messages/' + messageId, {
      method: 'DELETE',
      headers: authHeaders(token1),
    });
    assert.strictEqual(res.status, 204);
  });

  it('DELETE /messages/:messageId — возвращает 404 для несуществующего сообщения', async () => {
    const res = await fetch(baseUrl + '/messages/99999', {
      method: 'DELETE',
      headers: authHeaders(token1),
    });
    assert.strictEqual(res.status, 404);
  });
});
