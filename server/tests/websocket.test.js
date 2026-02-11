/**
 * Тесты WebSocket соединений и валидации сообщений
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { WebSocket } from 'ws';
import { server } from '../index.js';
import { register, login } from './helpers.js';

let baseUrl;
let wsUrl;
let token1;
let token2;
let userId1;
let userId2;

before(async () => {
  await new Promise((res) => {
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      baseUrl = `http://127.0.0.1:${port}`;
      wsUrl = `ws://127.0.0.1:${port}/ws`;
      res();
    });
  });
  
  const r1 = await register(baseUrl, { username: 'wsuser1', password: 'pass123' });
  const r2 = await register(baseUrl, { username: 'wsuser2', password: 'pass456' });
  assert.strictEqual(r1.status, 201);
  assert.strictEqual(r2.status, 201);
  token1 = r1.data.token;
  token2 = r2.data.token;
  userId1 = r1.data.user.id;
  userId2 = r2.data.user.id;
});

after(() => server.close());

describe('WebSocket', () => {
  it('должен подключиться с валидным токеном', async () => {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`${wsUrl}?token=${token1}`);
      ws.on('open', () => {
        ws.close();
        resolve();
      });
      ws.on('error', reject);
    });
  });

  it('должен отклонить подключение без токена', async () => {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      ws.on('open', () => {
        ws.close();
        reject(new Error('Подключение должно быть отклонено'));
      });
      ws.on('error', (error) => {
        assert.ok(error.message.includes('401') || error.message.includes('Unauthorized'));
        resolve();
      });
    });
  });

  it('должен отклонить подключение с невалидным токеном', async () => {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`${wsUrl}?token=invalid-token`);
      ws.on('open', () => {
        ws.close();
        reject(new Error('Подключение должно быть отклонено'));
      });
      ws.on('error', (error) => {
        assert.ok(error.message.includes('401') || error.message.includes('Unauthorized'));
        resolve();
      });
    });
  });

  it('должен валидировать call_signal сообщения', async () => {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`${wsUrl}?token=${token1}`);
      let messageReceived = false;
      
      ws.on('open', () => {
        // Отправляем невалидное сообщение без type
        ws.send(JSON.stringify({ toUserId: userId2, signal: 'offer' }));
        
        // Отправляем невалидное сообщение без toUserId
        ws.send(JSON.stringify({ type: 'call_signal', signal: 'offer' }));
        
        // Отправляем невалидное сообщение с невалидным toUserId
        ws.send(JSON.stringify({ type: 'call_signal', toUserId: -1, signal: 'offer' }));
        
        // Отправляем валидное сообщение
        ws.send(JSON.stringify({ 
          type: 'call_signal', 
          toUserId: userId2, 
          signal: 'offer',
          payload: { sdp: 'test', type: 'offer' }
        }));
        
        setTimeout(() => {
          ws.close();
          if (!messageReceived) {
            reject(new Error('Валидное сообщение должно быть обработано'));
          } else {
            resolve();
          }
        }, 500);
      });
      
      ws.on('message', (data) => {
        const message = JSON.parse(data.toString());
        if (message.type === 'call_signal' && message.fromUserId === userId1) {
          messageReceived = true;
        }
      });
      
      ws.on('error', reject);
    });
  });

  it('должен обрабатывать отклонение звонка и создавать сообщение о пропущенном звонке', async () => {
    return new Promise(async (resolve, reject) => {
      const ws1 = new WebSocket(`${wsUrl}?token=${token1}`);
      const ws2 = new WebSocket(`${wsUrl}?token=${token2}`);
      let missedCallReceived = false;
      
      await new Promise((res) => {
        ws1.on('open', () => ws2.on('open', res));
      });
      
      // user1 звонит user2
      ws1.send(JSON.stringify({ 
        type: 'call_signal', 
        toUserId: userId2, 
        signal: 'offer',
        payload: { sdp: 'test', type: 'offer' }
      }));
      
      // Ждем получения offer
      await new Promise((res) => {
        ws2.on('message', (data) => {
          const msg = JSON.parse(data.toString());
          if (msg.type === 'call_signal' && msg.signal === 'offer') {
            res();
          }
        });
      });
      
      // user2 отклоняет звонок
      ws2.send(JSON.stringify({ 
        type: 'call_signal', 
        toUserId: userId1, 
        signal: 'reject'
      }));
      
      // Проверяем, что user1 получил сообщение о пропущенном звонке
      ws1.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'new_message' && msg.message_type === 'missed_call') {
          assert.strictEqual(msg.sender_id, userId2);
          assert.strictEqual(msg.receiver_id, userId1);
          missedCallReceived = true;
        }
      });
      
      setTimeout(() => {
        ws1.close();
        ws2.close();
        if (missedCallReceived) {
          resolve();
        } else {
          reject(new Error('Сообщение о пропущенном звонке не было создано'));
        }
      }, 1000);
      
      ws1.on('error', reject);
      ws2.on('error', reject);
    });
  });
});
