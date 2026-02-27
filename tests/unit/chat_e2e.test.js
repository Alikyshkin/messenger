/**
 * E2E: Логин → Создание чата → Отправка сообщения → Получение сообщения (2 клиента)
 * Рекомендуемый первый поток по docs/testing_strategy.md
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { WebSocket } from 'ws';
import { server } from '../../server/index.js';
import { createChatPair } from './core/user_factory.js';
import { sendMessage, getMessages } from './core/chat_helpers.js';

let baseUrl;
let wsUrl;
let user1;
let user2;

before(async () => {
  await new Promise((res) => {
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      baseUrl = `http://127.0.0.1:${port}`;
      wsUrl = `ws://127.0.0.1:${port}/ws`;
      res();
    });
  });

  const pair = await createChatPair(baseUrl);
  user1 = pair.user1;
  user2 = pair.user2;
});

after(() => server.close());

describe('E2E: Login → Create chat → Send message → Receive message (2 clients)', () => {
  it('полный поток: user1 отправляет, user2 получает сообщение', async () => {
    const content = `E2E test message ${Date.now()}`;

    // 1. User1 отправляет сообщение user2 (создаётся чат 1-на-1)
    const sendRes = await sendMessage(baseUrl, user1.token, {
      receiverId: user2.user.id,
      content,
    });
    assert.strictEqual(sendRes.status, 201, `Send failed: ${JSON.stringify(sendRes.data)}`);
    assert.strictEqual(sendRes.data.content, content);
    assert.strictEqual(sendRes.data.sender_id, user1.user.id);
    assert.strictEqual(sendRes.data.receiver_id, user2.user.id);

    // 2. User2 получает сообщения (GET /messages/:peerId)
    const getRes = await getMessages(baseUrl, user2.token, user1.user.id);
    assert.strictEqual(getRes.status, 200);
    const messages = getRes.data?.data ?? getRes.data;
    assert.ok(Array.isArray(messages));
    const received = messages.find((m) => m.content === content);
    assert.ok(received, 'User2 должен видеть сообщение от user1');
    assert.strictEqual(received.sender_id, user1.user.id);
    assert.strictEqual(received.receiver_id, user2.user.id);
    assert.strictEqual(received.is_mine, false, 'Для user2 это чужое сообщение');
  });

  it('user1 видит свои отправленные сообщения', async () => {
    const content = `From user1 at ${Date.now()}`;
    await sendMessage(baseUrl, user1.token, {
      receiverId: user2.user.id,
      content,
    });

    const getRes = await getMessages(baseUrl, user1.token, user2.user.id);
    assert.strictEqual(getRes.status, 200);
    const messages = getRes.data?.data ?? getRes.data;
    const msg = messages.find((m) => m.content === content);
    assert.ok(msg);
    assert.strictEqual(msg.is_mine, true);
  });

  it('двусторонний обмен: user2 отвечает user1', async () => {
    const msg1 = `User1: ${Date.now()}`;
    const msg2 = `User2 reply: ${Date.now()}`;

    await sendMessage(baseUrl, user1.token, { receiverId: user2.user.id, content: msg1 });
    await sendMessage(baseUrl, user2.token, { receiverId: user1.user.id, content: msg2 });

    const u1Res = await getMessages(baseUrl, user1.token, user2.user.id);
    const u2Res = await getMessages(baseUrl, user2.token, user1.user.id);
    const u1Messages = u1Res.data?.data ?? u1Res.data;
    const u2Messages = u2Res.data?.data ?? u2Res.data;

    assert.ok(u1Messages.some((m) => m.content === msg2), 'User1 видит ответ user2');
    assert.ok(u2Messages.some((m) => m.content === msg1), 'User2 видит сообщение user1');
  });
});
