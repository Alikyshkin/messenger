// @ts-check
/**
 * Полное API-покрытие переписки: редактирование, удаление, онлайн-статус,
 * группы, реакции, опросы, геолокация, пагинация, поиск.
 * Запуск: npm run test:playwright:api
 */
import { test, expect } from '@playwright/test';
import { PASSWORD, unique, createContactPair } from './helpers.js';

// Использует baseURL из playwright.config.js (относительные пути)
const apiBase = () => '';

async function register(request, overrides = {}) {
  const username = overrides.username ?? unique();
  const res = await request.post(`/auth/register`, {
    data: {
      username,
      password: PASSWORD,
      displayName: overrides.displayName ?? `User ${username}`,
    },
  });
  const body = await res.json();
  return { username, token: body.token, user: body.user, id: body.user?.id };
}

// ─── helpers ────────────────────────────────────────────────────────────────

async function createGroup(request, creator, memberIds = [], name = null) {
  const res = await request.post(`/groups`, {
    headers: { Authorization: `Bearer ${creator.token}` },
    data: { name: name ?? `G_${Date.now()}`, member_ids: memberIds },
  });
  expect(res.status()).toBe(201);
  return res.json();
}

async function sendMsg(request, token, receiverId, content) {
  const res = await request.post(`/messages`, {
    headers: { Authorization: `Bearer ${token}` },
    data: { receiver_id: receiverId, content },
  });
  expect(res.status()).toBe(201);
  return res.json();
}

async function sendGroupMsg(request, token, groupId, content) {
  const res = await request.post(`/groups/${groupId}/messages`, {
    headers: { Authorization: `Bearer ${token}` },
    data: { content },
  });
  expect(res.status()).toBe(201);
  return res.json();
}

// ═══════════════════════════════════════════════
// 1. РЕДАКТИРОВАНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('Редактирование сообщений', () => {
  test('отправитель редактирует текстовое сообщение', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'original text');

    const editRes = await request.patch(`/messages/${msg.id}`, {
      headers: h1,
      data: { content: 'edited text' },
    });
    expect(editRes.status()).toBe(200);
    const edited = await editRes.json();
    expect(edited.content).toBe('edited text');
  });

  test('отредактированный текст виден в истории', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'before edit');

    await request.patch(`/messages/${msg.id}`, {
      headers: h1,
      data: { content: 'after edit' },
    });

    const histRes = await request.get(`/messages/${pair.user2.id}`, { headers: h1 });
    const data = await histRes.json();
    const found = (data.data ?? data).find((m) => m.id === msg.id);
    expect(found?.content).toBe('after edit');
  });

  test('получатель не может редактировать чужое сообщение', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'cannot touch');

    const editRes = await request.patch(`/messages/${msg.id}`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { content: 'hacked' },
    });
    expect(editRes.status()).toBe(403);
  });
});

// ═══════════════════════════════════════════════
// 2. УДАЛЕНИЕ ДЛЯ СЕБЯ (SOFT DELETE)
// ═══════════════════════════════════════════════

test.describe('Удаление для себя (soft delete)', () => {
  test('for_me=true возвращает 204', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'delete for me');

    const delRes = await request.delete(`/messages/${msg.id}?for_me=true`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    expect(delRes.status()).toBe(204);
  });

  test('после soft-delete сообщение пропадает у удалившего, но видно собеседнику', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'soft del target');

    await request.delete(`/messages/${msg.id}?for_me=true`, { headers: h1 });

    const hist1 = await request.get(`/messages/${pair.user2.id}`, { headers: h1 });
    const msgs1 = (await hist1.json()).data ?? (await hist1.json());
    // After calling .json() we get the data, need to re-check
    const d1 = await (await request.get(`/messages/${pair.user2.id}`, { headers: h1 })).json();
    expect((d1.data ?? d1).some((m) => m.id === msg.id)).toBeFalsy();

    const d2 = await (await request.get(`/messages/${pair.user1.id}`, { headers: h2 })).json();
    expect((d2.data ?? d2).some((m) => m.id === msg.id)).toBeTruthy();
  });

  test('hard delete: сообщение пропадает у обоих', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'delete for all');

    await request.delete(`/messages/${msg.id}`, { headers: h1 });

    const d1 = await (await request.get(`/messages/${pair.user2.id}`, { headers: h1 })).json();
    expect((d1.data ?? d1).some((m) => m.id === msg.id)).toBeFalsy();

    const d2 = await (await request.get(`/messages/${pair.user1.id}`, { headers: h2 })).json();
    expect((d2.data ?? d2).some((m) => m.id === msg.id)).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 3. ОНЛАЙН-СТАТУС
// ═══════════════════════════════════════════════

test.describe('Онлайн-статус', () => {
  test('GET /users/:id возвращает is_online и last_seen', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const res = await request.get(`/users/${pair.user2.id}`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    expect(res.status()).toBe(200);
    const user = await res.json();
    expect('is_online' in user).toBeTruthy();
    expect('last_seen' in user).toBeTruthy();
  });

  test('/chats включает is_online у peer', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    await sendMsg(request, pair.user1.token, pair.user2.id, 'online check');

    const chatsRes = await request.get(`/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const data = await chatsRes.json();
    const chat = (data.data ?? data).find((c) => c.peer?.id === pair.user2.id);
    expect(chat).toBeTruthy();
    expect('is_online' in (chat?.peer ?? {})).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 4. ГРУППОВЫЕ СООБЩЕНИЯ
// ═══════════════════════════════════════════════

test.describe('Групповые сообщения', () => {
  test('отправка и получение текстового сообщения', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);

    const msg = await sendGroupMsg(request, r1.token, group.id, 'привет группа');
    expect(msg.content).toBe('привет группа');
    expect(msg.group_id).toBe(group.id);

    const getRes = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    const data = await getRes.json();
    expect((data.data ?? data).some((m) => m.content === 'привет группа')).toBeTruthy();
  });

  test('участник видит сообщения основателя', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);
    const text = `group msg ${Date.now()}`;
    await sendGroupMsg(request, r1.token, group.id, text);

    const getRes = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    const data = await getRes.json();
    expect((data.data ?? data).some((m) => m.content === text)).toBeTruthy();
  });

  test('не-участник получает 404', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, []);

    const res = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    expect(res.status()).toBe(404);
  });

  test('sender_display_name присутствует в ответе', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);
    await sendGroupMsg(request, r1.token, group.id, 'name check');

    const getRes = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    const data = await getRes.json();
    const found = (data.data ?? data).find((m) => m.content === 'name check');
    expect(found?.sender_display_name).toBeTruthy();
  });

  test('пагинация группы через before', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    for (let i = 0; i < 5; i++) {
      await sendGroupMsg(request, r1.token, group.id, `msg ${i}`);
    }

    const allData = await (await request.get(`/groups/${group.id}/messages?limit=100`, { headers: h1 })).json();
    const allMsgs = allData.data ?? allData;
    const pivotId = allMsgs[allMsgs.length - 1]?.id;

    const beforeData = await (await request.get(
      `/groups/${group.id}/messages?limit=2&before=${pivotId}`,
      { headers: h1 }
    )).json();
    const beforeMsgs = beforeData.data ?? beforeData;
    expect(beforeMsgs.every((m) => m.id < pivotId)).toBeTruthy();
    expect(beforeMsgs.length).toBeLessThanOrEqual(2);
  });
});

// ═══════════════════════════════════════════════
// 5. РЕАКЦИИ В ГРУППОВЫХ СООБЩЕНИЯХ
// ═══════════════════════════════════════════════

test.describe('Реакции в группах', () => {
  async function setupGroupMsg(request) {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);
    const msg = await sendGroupMsg(request, r1.token, group.id, 'react me');
    return { r1, r2, group, msg };
  }

  test('добавить реакцию на групповое сообщение', async ({ request }) => {
    const { r2, group, msg } = await setupGroupMsg(request);

    const rRes = await request.post(
      `/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: { Authorization: `Bearer ${r2.token}` }, data: { emoji: '❤️' } }
    );
    expect(rRes.status()).toBe(200);
    const body = await rRes.json();
    expect(body.reactions.some((r) => r.emoji === '❤️')).toBeTruthy();
  });

  test('повторная реакция снимает её', async ({ request }) => {
    const { r1, group, msg } = await setupGroupMsg(request);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    await request.post(
      `/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h1, data: { emoji: '👍' } }
    );
    const r2 = await request.post(
      `/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h1, data: { emoji: '👍' } }
    );
    const body = await r2.json();
    const thumbs = body.reactions.find((r) => r.emoji === '👍');
    expect(!thumbs || thumbs.user_ids.length === 0).toBeTruthy();
  });

  test('два пользователя ставят одну реакцию — счётчик 2', async ({ request }) => {
    const { r1, r2, group, msg } = await setupGroupMsg(request);

    await request.post(
      `/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: { Authorization: `Bearer ${r1.token}` }, data: { emoji: '🔥' } }
    );
    const rRes = await request.post(
      `/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: { Authorization: `Bearer ${r2.token}` }, data: { emoji: '🔥' } }
    );
    const body = await rRes.json();
    const fire = body.reactions.find((r) => r.emoji === '🔥');
    expect(fire?.user_ids.length).toBe(2);
  });
});

// ═══════════════════════════════════════════════
// 6. ПРОЧТЕНИЕ ГРУППОВОГО ЧАТА
// ═══════════════════════════════════════════════

test.describe('Прочтение групп', () => {
  test('PATCH /groups/:id/read обнуляет unread_count', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    let lastMsgId;
    for (let i = 0; i < 3; i++) {
      const m = await sendGroupMsg(request, r1.token, group.id, `unread group ${i}`);
      lastMsgId = m.id;
    }

    const chats1 = await (await request.get(`/chats`, { headers: h2 })).json();
    const chat1 = (chats1.data ?? chats1).find((c) => c.group?.id === group.id);
    expect(chat1?.unread_count).toBe(3);

    await request.patch(`/groups/${group.id}/read`, {
      headers: h2,
      data: { last_message_id: lastMsgId },
    });

    const chats2 = await (await request.get(`/chats`, { headers: h2 })).json();
    const chat2 = (chats2.data ?? chats2).find((c) => c.group?.id === group.id);
    expect(chat2?.unread_count).toBe(0);
  });
});

// ═══════════════════════════════════════════════
// 7. УПРАВЛЕНИЕ УЧАСТНИКАМИ
// ═══════════════════════════════════════════════

test.describe('Участники группы', () => {
  test('admin добавляет участника', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, []);

    const addRes = await request.post(`/groups/${group.id}/members`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { user_ids: [r2.id] },
    });
    expect(addRes.status()).toBe(204);

    const msgRes = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    expect(msgRes.status()).toBe(200);
  });

  test('не-admin не может добавить участника', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const r3 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);

    const addRes = await request.post(`/groups/${group.id}/members`, {
      headers: { Authorization: `Bearer ${r2.token}` },
      data: { user_ids: [r3.id] },
    });
    expect(addRes.status()).toBe(403);
  });

  test('участник может покинуть группу', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);

    const leaveRes = await request.delete(
      `/groups/${group.id}/members/${r2.id}`,
      { headers: { Authorization: `Bearer ${r2.token}` } }
    );
    expect(leaveRes.status()).toBe(204);

    const msgRes = await request.get(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    expect(msgRes.status()).toBe(404);
  });

  test('группа удаляется когда выходит последний участник', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);

    await request.delete(
      `/groups/${group.id}/members/${r1.id}`,
      { headers: { Authorization: `Bearer ${r1.token}` } }
    );

    const res = await request.get(`/groups/${group.id}`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    expect(res.status()).toBe(404);
  });

  test('GET /groups/:id возвращает список участников', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);

    const infoRes = await request.get(`/groups/${group.id}`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    expect(infoRes.status()).toBe(200);
    const info = await infoRes.json();
    expect(Array.isArray(info.members)).toBeTruthy();
    expect(info.members.length).toBe(2);
    expect(info.members.some((m) => m.id === r1.id)).toBeTruthy();
    expect(info.members.some((m) => m.id === r2.id)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 8. ГРУППОВЫЕ ОПРОСЫ
// ═══════════════════════════════════════════════

test.describe('Групповые опросы', () => {
  test('создание опроса в группе', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);

    const pollRes = await request.post(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: {
        type: 'poll',
        question: 'Лучший язык?',
        options: ['Dart', 'JavaScript', 'Python'],
      },
    });
    expect(pollRes.status()).toBe(201);
    const poll = await pollRes.json();
    expect(poll.message_type).toBe('poll');
    expect(poll.poll_id).toBeTruthy();
    expect(poll.poll?.question).toBe('Лучший язык?');
    expect(poll.poll?.options.length).toBe(3);
  });

  test('голосование в групповом опросе', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id]);

    const pollRes = await request.post(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { type: 'poll', question: 'Голосуем?', options: ['Да', 'Нет'] },
    });
    const pollMsg = await pollRes.json();

    const voteRes = await request.post(
      `/groups/${group.id}/polls/${pollMsg.poll_id}/vote`,
      { headers: { Authorization: `Bearer ${r2.token}` }, data: { option_index: 0 } }
    );
    expect(voteRes.status()).toBe(200);
    const voteBody = await voteRes.json();
    expect(voteBody.options?.[0]?.votes).toBeGreaterThan(0);
  });
});

// ═══════════════════════════════════════════════
// 9. REPLY И FORWARD В ГРУППАХ
// ═══════════════════════════════════════════════

test.describe('Reply и Forward в группах', () => {
  test('ответ на сообщение в группе содержит reply_to_id', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const msg = await sendGroupMsg(request, r1.token, group.id, 'original');

    const replyRes = await request.post(`/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'reply!', reply_to_id: msg.id },
    });
    expect(replyRes.status()).toBe(201);
    const reply = await replyRes.json();
    expect(reply.reply_to_id).toBe(msg.id);
  });

  test('пересылка в группу', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);

    const fwdRes = await request.post(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: {
        content: 'forwarded content',
        is_forwarded: true,
        forward_from_display_name: 'Источник',
      },
    });
    expect(fwdRes.status()).toBe(201);
    const fwd = await fwdRes.json();
    expect(fwd.is_forwarded).toBe(true);
    expect(fwd.forward_from_display_name).toBe('Источник');
  });
});

// ═══════════════════════════════════════════════
// 10. МНОЖЕСТВЕННЫЕ РЕАКЦИИ 1-1
// ═══════════════════════════════════════════════

test.describe('Множественные реакции (1-1)', () => {
  test('два пользователя ставят одинаковую реакцию — счётчик 2', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'multi react');

    await request.post(`/messages/${msg.id}/reaction`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { emoji: '😂' },
    });
    const r2 = await request.post(`/messages/${msg.id}/reaction`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { emoji: '😂' },
    });
    const laugh = (await r2.json()).reactions.find((r) => r.emoji === '😂');
    expect(laugh?.user_ids.length).toBe(2);
  });

  test('замена реакции', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const msg = await sendMsg(request, pair.user1.token, pair.user2.id, 'switch react');
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    await request.post(`/messages/${msg.id}/reaction`, {
      headers: h1, data: { emoji: '👍' },
    });
    const r2 = await request.post(`/messages/${msg.id}/reaction`, {
      headers: h1, data: { emoji: '❤️' },
    });
    const body = await r2.json();
    const heart = body.reactions.find((r) => r.emoji === '❤️');
    const thumbs = body.reactions.find((r) => r.emoji === '👍');
    expect(heart?.user_ids.includes(pair.user1.id)).toBeTruthy();
    expect(!thumbs || !thumbs.user_ids.includes(pair.user1.id)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 11. СПИСОК ЧАТОВ С ГРУППАМИ
// ═══════════════════════════════════════════════

test.describe('Список чатов с группами', () => {
  test('группа появляется в /chats после первого сообщения', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);
    await sendGroupMsg(request, r1.token, group.id, 'first group message');

    const chatsRes = await request.get(`/chats`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    const data = await chatsRes.json();
    expect((data.data ?? data).some((c) => c.group?.id === group.id)).toBeTruthy();
  });

  test('последнее сообщение группы в превью чата', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);
    const lastText = `preview ${Date.now()}`;
    await sendGroupMsg(request, r1.token, group.id, 'first');
    await sendGroupMsg(request, r1.token, group.id, lastText);

    const chatsRes = await request.get(`/chats`, {
      headers: { Authorization: `Bearer ${r1.token}` },
    });
    const data = await chatsRes.json();
    const chat = (data.data ?? data).find((c) => c.group?.id === group.id);
    expect(chat?.last_message?.content).toBe(lastText);
  });
});

// ═══════════════════════════════════════════════
// 12. ПАГИНАЦИЯ С КУРСОРОМ (before)
// ═══════════════════════════════════════════════

test.describe('Пагинация с курсором', () => {
  test('before возвращает более старые сообщения (1-1)', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    for (let i = 0; i < 5; i++) {
      await sendMsg(request, pair.user1.token, pair.user2.id, `cursor msg ${i}`);
    }

    const allData = await (await request.get(`/messages/${pair.user2.id}?limit=100`, { headers: h1 })).json();
    const allMsgs = allData.data ?? allData;
    const pivotId = allMsgs[allMsgs.length - 1]?.id;

    const pageData = await (await request.get(
      `/messages/${pair.user2.id}?limit=2&before=${pivotId}`,
      { headers: h1 }
    )).json();
    const pageMsgs = pageData.data ?? pageData;
    expect(pageMsgs.every((m) => m.id < pivotId)).toBeTruthy();
    expect(pageMsgs.length).toBeLessThanOrEqual(2);
  });

  test('hasMore=true когда сообщений больше limit', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    for (let i = 0; i < 5; i++) {
      await sendMsg(request, pair.user1.token, pair.user2.id, `has more ${i}`);
    }

    const data = await (await request.get(`/messages/${pair.user2.id}?limit=2`, { headers: h1 })).json();
    expect(data.pagination?.hasMore).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 13. ОБНОВЛЕНИЕ ГРУППЫ
// ═══════════════════════════════════════════════

test.describe('Обновление группы', () => {
  test('admin переименовывает группу', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, [], 'OldName');

    const patchRes = await request.patch(`/groups/${group.id}`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { name: 'NewName' },
    });
    expect(patchRes.status()).toBe(200);
    const updated = await patchRes.json();
    expect(updated.name).toBe('NewName');
  });

  test('не-admin не может переименовать группу', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    const group = await createGroup(request, r1, [r2.id], 'AdminGroup');

    const patchRes = await request.patch(`/groups/${group.id}`, {
      headers: { Authorization: `Bearer ${r2.token}` },
      data: { name: 'HackedName' },
    });
    expect(patchRes.status()).toBe(403);
  });
});

// ═══════════════════════════════════════════════
// 14. ГЕОЛОКАЦИЯ
// ═══════════════════════════════════════════════

test.describe('Геолокация', () => {
  test('отправка геолокации в 1-1 чат', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());

    const res = await request.post(`/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: {
        receiver_id: pair.user2.id,
        type: 'location',
        lat: 55.7558,
        lng: 37.6173,
        location_label: 'Москва',
      },
    });
    expect(res.status()).toBe(201);
    const msg = await res.json();
    expect(msg.message_type).toBe('location');
    const coords = JSON.parse(msg.content);
    expect(coords.lat).toBeCloseTo(55.7558, 3);
    expect(coords.lng).toBeCloseTo(37.6173, 3);
    expect(coords.label).toBe('Москва');
  });

  test('отправка геолокации в группу', async ({ request }) => {
    const r1 = await register(request);
    const group = await createGroup(request, r1, []);

    const res = await request.post(`/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { type: 'location', lat: 48.8566, lng: 2.3522, location_label: 'Париж' },
    });
    expect(res.status()).toBe(201);
    const msg = await res.json();
    expect(msg.message_type).toBe('location');
  });
});

// ═══════════════════════════════════════════════
// 15. СПИСОК ГРУПП
// ═══════════════════════════════════════════════

test.describe('Список групп', () => {
  test('GET /groups возвращает группы пользователя', async ({ request }) => {
    const r1 = await register(request);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    await createGroup(request, r1, [], 'MyGroup1');
    await createGroup(request, r1, [], 'MyGroup2');

    const res = await request.get(`/groups`, { headers: h1 });
    expect(res.status()).toBe(200);
    const data = await res.json();
    const groups = data.data ?? data;
    expect(groups.some((g) => g.name === 'MyGroup1')).toBeTruthy();
    expect(groups.some((g) => g.name === 'MyGroup2')).toBeTruthy();
  });

  test('чужие группы не видны', async ({ request }) => {
    const r1 = await register(request);
    const r2 = await register(request);
    await createGroup(request, r1, [], 'PrivateGroup');

    const res = await request.get(`/groups`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    const data = await res.json();
    expect((data.data ?? data).some((g) => g.name === 'PrivateGroup')).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 16. ПОЛНОТЕКСТОВЫЙ ПОИСК
// ═══════════════════════════════════════════════

test.describe('Полнотекстовый поиск', () => {
  test('поиск по тексту находит сообщение', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const unique_text = `findme${Date.now()}`;

    await sendMsg(request, pair.user1.token, pair.user2.id, unique_text);
    // Дать FTS индексу обновиться
    await new Promise((r) => setTimeout(r, 300));

    const res = await request.get(
      `/search/messages?q=${encodeURIComponent(unique_text)}`,
      { headers: h1 }
    );
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect((data.data ?? []).some((m) => m.content?.includes(unique_text))).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 17. ОПРОСЫ С МНОЖЕСТВЕННЫМ ВЫБОРОМ
// ═══════════════════════════════════════════════

test.describe('Опросы: множественный выбор', () => {
  test('multiple=true позволяет голосовать за несколько вариантов', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());

    const sendRes = await request.post(`/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: {
        receiver_id: pair.user2.id,
        type: 'poll',
        question: 'Что вы любите?',
        options: ['Кошки', 'Собаки', 'Рыбки'],
        multiple: true,
      },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();

    const voteRes = await request.post(`/polls/${msg.poll_id}/vote`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { option_indexes: [0, 2] },
    });
    expect(voteRes.status()).toBe(200);
    const body = await voteRes.json();
    const myVotes = body.options.filter((o) => o.voted);
    expect(myVotes.length).toBe(2);
  });
});

// ═══════════════════════════════════════════════
// 18. SYNC API
// ═══════════════════════════════════════════════

test.describe('Sync API', () => {
  test('GET /sync/status возвращает статус синхронизации', async ({ request }) => {
    const { token } = await register(request);
    const res = await request.get(`/sync/status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect(data.synced).toBeTruthy();
  });
});
