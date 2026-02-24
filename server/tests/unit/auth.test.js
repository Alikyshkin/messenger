/**
 * Тесты auth API. Запуск: npm test (NODE_ENV=test, тестовая БД).
 * В прод не попадают: папка tests/ не разворачивается как прод-код.
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import crypto from 'crypto';
import db from '../../db.js';
import { app, server } from '../../index.js';
import { fetchJson, register, login, authHeaders } from '../helpers.js';

let baseUrl;

before(async () => {
  await new Promise((res) => {
    server.listen(0, '127.0.0.1', () => {
      baseUrl = `http://127.0.0.1:${server.address().port}`;
      res();
    });
  });
});

after(() => server.close());

describe('Auth', () => {
  it('POST /auth/register — создаёт пользователя и возвращает token', async () => {
    const { status, data } = await register(baseUrl, {
      username: 'reguser',
      password: 'pass123',
      displayName: 'Reg User',
    });
    assert.strictEqual(status, 201);
    assert.ok(data.token);
    assert.strictEqual(data.user.username, 'reguser');
    assert.strictEqual(data.user.display_name, 'Reg User');
  });

  it('POST /auth/register — с email', async () => {
    const { status, data } = await register(baseUrl, {
      username: 'withemail',
      password: 'pass123',
      email: 'test@example.com',
    });
    assert.strictEqual(status, 201);
    assert.strictEqual(data.user.email, 'test@example.com');
  });

  it('POST /auth/register — возвращает 409 при дублировании username', async () => {
    await register(baseUrl, { username: 'dupuser', password: 'pass123' });
    const { status } = await register(baseUrl, { username: 'dupuser', password: 'other456' });
    assert.strictEqual(status, 409);
  });

  it('POST /auth/register — отклоняет короткий username', async () => {
    const { status } = await register(baseUrl, { username: 'ab', password: 'pass123' });
    assert.strictEqual(status, 400);
  });

  it('POST /auth/register — отклоняет короткий пароль', async () => {
    const { status } = await register(baseUrl, { username: 'longuser', password: '12345' });
    assert.strictEqual(status, 400);
  });

  it('POST /auth/register — отклоняет некорректный email', async () => {
    const { status } = await register(baseUrl, {
      username: 'badmail',
      password: 'pass123',
      email: 'not-an-email',
    });
    assert.strictEqual(status, 400);
  });

  it('POST /auth/login — возвращает token', async () => {
    await register(baseUrl, { username: 'loginuser', password: 'mypass' });
    const { status, data } = await login(baseUrl, 'loginuser', 'mypass');
    assert.strictEqual(status, 200);
    assert.ok(data.token);
    assert.strictEqual(data.user.username, 'loginuser');
  });

  it('POST /auth/login — 401 при неверном пароле', async () => {
    const { status } = await login(baseUrl, 'loginuser', 'wrong');
    assert.strictEqual(status, 401);
  });

  it('POST /auth/forgot-password — 200 и сообщение (не раскрывает наличие email)', async () => {
    const { status, data } = await fetchJson(baseUrl, '/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ email: 'nonexistent@example.com' }),
    });
    assert.strictEqual(status, 200);
    assert.ok(data.message);
  });

  it('POST /auth/reset-password — 400 без токена', async () => {
    const { status } = await fetchJson(baseUrl, '/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({ newPassword: 'newpass123' }),
    });
    assert.strictEqual(status, 400);
  });

  it('POST /auth/reset-password — успех по валидному токену', async () => {
    await register(baseUrl, { username: 'resetusera', password: 'oldpass', email: 'reset@example.com' });
    const user = db.prepare('SELECT id FROM users WHERE email = ?').get('reset@example.com');
    assert.ok(user);
    const token = 'test-reset-token-xyz';
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const expiresAt = new Date(Date.now() + 3600000).toISOString();
    db.prepare(
      'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)'
    ).run(user.id, tokenHash, expiresAt);

    const { status } = await fetchJson(baseUrl, '/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({ token, newPassword: 'newpass123' }),
    });
    assert.strictEqual(status, 200);

    const loginRes = await login(baseUrl, 'resetusera', 'newpass123');
    assert.strictEqual(loginRes.status, 200);
  });

  it('POST /auth/change-password — 401 без токена', async () => {
    const { status } = await fetchJson(baseUrl, '/auth/change-password', {
      method: 'POST',
      headers: {},
      body: JSON.stringify({ currentPassword: 'x', newPassword: 'y' }),
    });
    assert.strictEqual(status, 401);
  });

  it('POST /auth/change-password — успех с текущим паролем', async () => {
    await register(baseUrl, { username: 'chpuser', password: 'oldpass' });
    const { data: loginData } = await login(baseUrl, 'chpuser', 'oldpass');
    const { status } = await fetchJson(baseUrl, '/auth/change-password', {
      method: 'POST',
      headers: authHeaders(loginData.token),
      body: JSON.stringify({ currentPassword: 'oldpass', newPassword: 'newpass456' }),
    });
    assert.strictEqual(status, 200);
    const loginAfter = await login(baseUrl, 'chpuser', 'newpass456');
    assert.strictEqual(loginAfter.status, 200);
  });
});
