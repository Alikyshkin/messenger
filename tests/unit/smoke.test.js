/**
 * Smoke suite: на каждом коммите/PR.
 * Состав: Логин, Отправка и получение сообщения, Один звонок (аудио).
 */
import { describe, it, before, after } from 'node:test';
import { login } from './helpers.js';
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

describe('Smoke: Login', () => {
  it('логин с валидными кредами', async () => {
    const { status, data } = await login(baseUrl, user1.username, user1.password);
    assert.strictEqual(status, 200);
    assert.ok(data.token);
    assert.strictEqual(data.user.username, user1.username);
  });
});

describe('Smoke: Отправка и получение сообщения', () => {
  it('отправка и получение сообщения', async () => {
    const content = `Smoke msg ${Date.now()}`;
    const sendRes = await sendMessage(baseUrl, user1.token, {
      receiverId: user2.user.id,
      content,
    });
    assert.strictEqual(sendRes.status, 201);

    const getRes = await getMessages(baseUrl, user2.token, user1.user.id);
    assert.strictEqual(getRes.status, 200);
    const messages = getRes.data?.data ?? getRes.data;
    const msg = messages.find((m) => m.content === content);
    assert.ok(msg, 'Получатель должен видеть сообщение');
  });
});

describe('Smoke: Аудиозвонок (offer/reject)', () => {
  it('звонящий отправляет offer, принимающий отклоняет — создаётся missed_call', async () => {
    return new Promise(async (resolve, reject) => {
      const ws1 = new WebSocket(`${wsUrl}?token=${user1.token}`);
      const ws2 = new WebSocket(`${wsUrl}?token=${user2.token}`);

      await new Promise((res) => {
        ws1.on('open', () => ws2.on('open', res));
      });

      let missedCallReceived = false;

      ws1.send(
        JSON.stringify({
          type: 'call_signal',
          toUserId: user2.user.id,
          signal: 'offer',
          payload: { sdp: 'test', type: 'offer' },
        })
      );

      await new Promise((res) => {
        ws2.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'call_signal' && msg.signal === 'offer') res();
        });
      });

      ws2.send(
        JSON.stringify({
          type: 'call_signal',
          toUserId: user1.user.id,
          signal: 'reject',
        })
      );

      ws1.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'new_message' && msg.message_type === 'missed_call') {
          missedCallReceived = true;
        }
      });

      setTimeout(() => {
        ws1.close();
        ws2.close();
        assert.ok(missedCallReceived, 'Сообщение о пропущенном звонке должно быть создано');
        resolve();
      }, 800);

      ws1.on('error', reject);
      ws2.on('error', reject);
    });
  });
});
