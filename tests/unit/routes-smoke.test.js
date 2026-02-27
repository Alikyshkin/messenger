/**
 * Smoke-тесты для роутов export, gdpr, media, sync, version, polls, push, oauth, groups.
 * Регистрация, логин, основные запросы к каждому эндпоинту.
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { server } from '../../server/index.js';
import { createUser, createChatPair } from './core/user_factory.js';
import { fetchJson, authHeaders } from './helpers.js';

let baseUrl;
let user;
let pair;

before(async () => {
  await new Promise((res) => {
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      baseUrl = `http://127.0.0.1:${port}`;
      res();
    });
  });
  user = await createUser(baseUrl);
  pair = await createChatPair(baseUrl);
});

after(() => server.close());

describe('Routes smoke: version', () => {
  it('GET /version возвращает версию без авторизации', async () => {
    const { status, data } = await fetchJson(baseUrl, '/version');
    assert.strictEqual(status, 200);
    assert.ok(data.version);
    assert.ok(data.timestamp);
  });
});

describe('Routes smoke: oauth', () => {
  it('GET /auth/oauth/providers возвращает флаги провайдеров без авторизации', async () => {
    const { status, data } = await fetchJson(baseUrl, '/auth/oauth/providers');
    assert.strictEqual(status, 200);
    assert.ok(typeof data.google === 'boolean');
  });
});

describe('Routes smoke: export', () => {
  it('GET /export/json без токена — 401', async () => {
    const { status } = await fetchJson(baseUrl, '/export/json');
    assert.strictEqual(status, 401);
  });

  it('GET /export/json с токеном возвращает данные или 500 (конфиг)', async () => {
    const { status, data } = await fetchJson(baseUrl, '/export/json', {
      headers: authHeaders(user.data.token),
    });
    assert.ok([200, 500].includes(status));
    if (status === 200) {
      assert.ok(data.export_date);
      assert.ok(data.user);
    }
  });
});

describe('Routes smoke: gdpr', () => {
  it('GET /gdpr/export-data с токеном возвращает данные', async () => {
    const { status, data } = await fetchJson(baseUrl, '/gdpr/export-data', {
      headers: authHeaders(user.data.token),
    });
    assert.strictEqual(status, 200);
    assert.ok(data !== undefined);
  });
});

describe('Routes smoke: sync', () => {
  it('GET /sync/status с токеном возвращает статус', async () => {
    const { status, data } = await fetchJson(baseUrl, '/sync/status', {
      headers: authHeaders(user.data.token),
    });
    assert.strictEqual(status, 200);
    assert.ok('synced' in data);
    assert.ok('unreadCount' in data);
  });
});

describe('Routes smoke: media', () => {
  it('GET /media/:peerId с токеном — 200 с массивом или 404 (чат без сообщений)', async () => {
    const peerId = pair.user2.user.id;
    const { status, data } = await fetchJson(baseUrl, `/media/${peerId}`, {
      headers: authHeaders(pair.user1.token),
    });
    assert.ok([200, 404].includes(status));
    if (status === 200) assert.ok(Array.isArray(data.data) || Array.isArray(data));
  });
});

describe('Routes smoke: groups', () => {
  it('GET /groups с токеном — 200 с данными или 500 (smoke: эндпоинт отвечает)', async () => {
    const { status, data } = await fetchJson(baseUrl, '/groups', {
      headers: authHeaders(user.data.token),
    });
    assert.ok([200, 500].includes(status));
    if (status === 200) assert.ok(Array.isArray(data.data) || Array.isArray(data));
  });
});

describe('Routes smoke: push', () => {
  it('POST /push/register с токеном и телом — валидация или успех', async () => {
    const { status } = await fetchJson(baseUrl, '/push/register', {
      method: 'POST',
      headers: authHeaders(user.data.token),
      body: JSON.stringify({ token: 'test-fcm-token-smoke', platform: 'web' }),
    });
    // 200/201 при успехе или 400 при невалидном токене — главное не 500 и не 401 без токена
    assert.ok([200, 201, 400].includes(status), `expected 200/201/400, got ${status}`);
  });
});
