/**
 * Тесты users, messages, health. Запуск: npm test.
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { server } from '../index.js';
import { fetchJson, register, login, authHeaders } from './helpers.js';

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
  const r1 = await register(baseUrl, { username: 'apiuser1', password: 'pass123' });
  const r2 = await register(baseUrl, { username: 'apiuser2', password: 'pass456' });
  assert.strictEqual(r1.status, 201, 'register user1: ' + JSON.stringify(r1.data));
  assert.strictEqual(r2.status, 201, 'register user2: ' + JSON.stringify(r2.data));
  token1 = r1.data.token;
  token2 = r2.data.token;
  userId1 = r1.data.user.id;
  userId2 = r2.data.user.id;
});

after(() => server.close());

describe('Health', () => {
  it('GET /health returns ok', async () => {
    const { status, data } = await fetchJson(baseUrl, '/health');
    assert.strictEqual(status, 200);
    assert.strictEqual(data.ok, true);
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
    assert.ok(Array.isArray(data));
    assert.strictEqual(data.length, 0);
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
    assert.ok(data.length >= 1);
    const msg = data.find((m) => m.content === 'Hello from 1');
    assert.ok(msg);
    assert.strictEqual(msg.is_mine, true);
  });
});
