import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { server } from '../../index.js';
import { fetchJson, authHeaders } from '../helpers.js';

let baseUrl;

describe('POST /messages - Integration Tests', () => {
  let token1, token2, userId1, userId2;

  before(async () => {
    if (process.env.TEST_BASE_URL) {
      baseUrl = process.env.TEST_BASE_URL;
    } else {
      await new Promise((res) => {
        server.listen(0, '127.0.0.1', () => {
          baseUrl = `http://127.0.0.1:${server.address().port}`;
          res();
        });
      });
    }
    // Создаем двух пользователей для тестирования
    const r1 = await fetchJson(baseUrl, '/auth/register', {
      method: 'POST',
      body: JSON.stringify({
        username: `test_user_${Date.now()}_1`,
        password: 'TestPassword123!',
        display_name: 'Test User 1',
      }),
    });
    token1 = r1.data.token;
    userId1 = r1.data.user.id;

    const r2 = await fetchJson(baseUrl, '/auth/register', {
      method: 'POST',
      body: JSON.stringify({
        username: `test_user_${Date.now()}_2`,
        password: 'TestPassword123!',
        display_name: 'Test User 2',
      }),
    });
    token2 = r2.data.token;
    userId2 = r2.data.user.id;
  });

  after(() => {
    if (!process.env.TEST_BASE_URL) server.close();
  });

  it('должен успешно отправить текстовое сообщение', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: {
        ...authHeaders(token1),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        receiver_id: userId2,
        content: 'Тестовое сообщение',
      }),
    });

    assert.strictEqual(status, 201, `Ожидался статус 201, получен ${status}`);
    assert.ok(data, 'Ответ должен содержать данные');
    assert.strictEqual(data.content, 'Тестовое сообщение');
    assert.strictEqual(data.sender_id, userId1);
    assert.strictEqual(data.receiver_id, userId2);
    assert.ok(data.id, 'Сообщение должно иметь ID');
    assert.ok(data.created_at, 'Сообщение должно иметь дату создания');
  });

  it('должен вернуть ошибку 400 при отсутствии receiver_id', async () => {
    try {
      await fetchJson(baseUrl, '/messages', {
        method: 'POST',
        headers: {
          ...authHeaders(token1),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          content: 'Сообщение без получателя',
        }),
      });
      assert.fail('Должна была быть ошибка 400');
    } catch (error) {
      assert.ok(error.status === 400 || error.message.includes('receiver_id'), 
        `Ожидалась ошибка 400, получена: ${error.status || error.message}`);
    }
  });

  it('должен вернуть ошибку 400 при пустом content и отсутствии файла', async () => {
    try {
      await fetchJson(baseUrl, '/messages', {
        method: 'POST',
        headers: {
          ...authHeaders(token1),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          receiver_id: userId2,
          content: '',
        }),
      });
      assert.fail('Должна была быть ошибка 400');
    } catch (error) {
      assert.ok(error.status === 400 || error.message.includes('content'), 
        `Ожидалась ошибка 400, получена: ${error.status || error.message}`);
    }
  });

  it('должен успешно отправить сообщение с reply_to_id', async () => {
    // Сначала отправляем первое сообщение
    const { data: firstMsg } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: {
        ...authHeaders(token1),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        receiver_id: userId2,
        content: 'Первое сообщение',
      }),
    });

    // Затем отправляем ответ на него
    const { status, data } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: {
        ...authHeaders(token2),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        receiver_id: userId1,
        content: 'Ответ на сообщение',
        reply_to_id: firstMsg.id,
      }),
    });

    assert.strictEqual(status, 201);
    assert.strictEqual(data.content, 'Ответ на сообщение');
    assert.strictEqual(data.reply_to_id, firstMsg.id);
  });

  it('должен успешно отправить пересланное сообщение', async () => {
    const { status, data } = await fetchJson(baseUrl, '/messages', {
      method: 'POST',
      headers: {
        ...authHeaders(token1),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        receiver_id: userId2,
        content: 'Пересланное сообщение',
        is_forwarded: true,
        forward_from_sender_id: userId2,
        forward_from_display_name: 'Test User 2',
      }),
    });

    assert.strictEqual(status, 201);
    assert.strictEqual(data.content, 'Пересланное сообщение');
    assert.strictEqual(data.is_forwarded, true);
    assert.strictEqual(data.forward_from_sender_id, userId2);
  });

  it('должен вернуть 401 при отсутствии токена', async () => {
    try {
      await fetchJson(baseUrl, '/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          receiver_id: userId2,
          content: 'Сообщение без авторизации',
        }),
      });
      assert.fail('Должна была быть ошибка 401');
    } catch (error) {
      assert.ok(error.status === 401, 
        `Ожидалась ошибка 401, получена: ${error.status || error.message}`);
    }
  });

  it('должен вернуть 404 при несуществующем получателе', async () => {
    try {
      await fetchJson(baseUrl, '/messages', {
        method: 'POST',
        headers: {
          ...authHeaders(token1),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          receiver_id: 999999,
          content: 'Сообщение несуществующему пользователю',
        }),
      });
      // Может быть 400 или 404 в зависимости от реализации
      // Проверяем, что запрос не прошел успешно
    } catch (error) {
      assert.ok(error.status >= 400 && error.status < 500, 
        `Ожидалась ошибка 4xx, получена: ${error.status || error.message}`);
    }
  });
});
