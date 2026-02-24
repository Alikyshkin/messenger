// @ts-check
/**
 * Тесты по API мессенджера: авторизация, чаты, друзья, сообщения.
 * Проверяют только API (request); без отдельно созданных страниц.
 * Визуальные/E2E-тесты по экранам приложения — в messenger.e2e.spec.js (client + server).
 */
import { test, expect } from '@playwright/test';

const unique = (prefix = 'user') => `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
const PASSWORD = 'TestPass123!';

function auth(request) {
  return {
    async register(overrides = {}) {
      const username = overrides.username ?? unique();
      const res = await request.post('/auth/register', {
        data: { username, password: PASSWORD, displayName: `User ${username}` },
      });
      const body = await res.json().catch(() => ({}));
      const token = body?.token;
      const user = body?.user ?? {};
      return { res, body, username, token, user };
    },
    async login(username, password = PASSWORD) {
      const res = await request.post('/auth/login', { data: { username, password } });
      const body = await res.json().catch(() => ({}));
      return { res, body, token: body.token, user: body.user };
    },
  };
}

function api(request, token) {
  const h = () => ({
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  });
  return {
    getMe: () => request.get('/users/me', { headers: h() }),
    getChats: () => request.get('/chats/', { headers: h() }),
    getContacts: () => request.get('/contacts/', { headers: h() }),
    addContact: (username) => request.post('/contacts/', { headers: h(), data: { username } }),
    deleteContact: (id) => request.delete(`/contacts/${id}`, { headers: h() }),
    getIncomingRequests: () => request.get('/contacts/requests/incoming', { headers: h() }),
    acceptRequest: (requestId) => request.post(`/contacts/requests/${requestId}/accept`, { headers: h() }),
    getMessages: (peerId) => request.get(`/messages/${peerId}`, { headers: h() }),
    sendMessage: (data) => request.post('/messages', { headers: h(), data }),
    deleteMessage: (messageId, forMe = false) =>
      request.delete(`/messages/${messageId}${forMe ? '?for_me=true' : ''}`, { headers: h() }),
    setPrivacyAllowAll: () => request.patch('/users/me/privacy', { headers: h(), data: { who_can_message: 'all' } }),
  };
}

// ---------- Auth ----------
test.describe('Авторизация', () => {
  test('регистрация нового пользователя возвращает 201 и токен', async ({ request }) => {
    const a = auth(request);
    const { res, body } = await a.register();
    expect(res.status()).toBe(201);
    expect(body.token).toBeDefined();
    expect(body.user?.id).toBeDefined();
    expect(body.user?.username).toBeDefined();
  });

  test('логин с верными данными возвращает 200 и токен', async ({ request }) => {
    const a = auth(request);
    const reg = await a.register();
    const { res, body } = await a.login(reg.username);
    expect(res.status()).toBe(200);
    expect(body.token).toBeDefined();
    expect(body.user?.username).toBe(reg.username);
  });

  test('логин с неверным паролем возвращает 401', async ({ request }) => {
    const a = auth(request);
    const reg = await a.register();
    const { res } = await a.login(reg.username, 'WrongPassword1!');
    expect(res.status()).toBe(401);
    const body = await res.json().catch(() => ({}));
    expect(body.error).toBeDefined();
  });

  test('логин с несуществующим пользователем возвращает 401', async ({ request }) => {
    const a = auth(request);
    const { res } = await a.login('nonexistent_user_xyz_123');
    expect(res.status()).toBe(401);
  });

  test('запрос без токена к защищённому эндпоинту возвращает 401', async ({ request }) => {
    const res = await request.get('/chats/');
    expect(res.status()).toBe(401);
  });
});

// ---------- Чаты и переход к сообщениям ----------
test.describe('Чаты / список сообщений', () => {
  test('после логина GET /chats возвращает 200 и массив чатов', async ({ request }) => {
    const a = auth(request);
    const reg = await a.register();
    expect(reg.res.status()).toBe(201);
    const apiCall = api(request, reg.token);
    const res = await apiCall.getChats();
    expect(res.status()).toBe(200);
    const json = await res.json();
    expect(Array.isArray(json.data)).toBe(true);
  });

  test('после отправки сообщения чат появляется в списке', async ({ request }) => {
    const a = auth(request);
    const u1 = await a.register();
    const u2 = await a.register();
    expect(u1.user?.id).toBeDefined();
    expect(u2.user?.id).toBeDefined();
    const api1 = api(request, u1.token);
    await api1.setPrivacyAllowAll();
    await api(request, u2.token).setPrivacyAllowAll();
    await api1.sendMessage({ receiver_id: u2.user.id, content: 'Привет' });
    const chatsRes = await api1.getChats();
    expect(chatsRes.status()).toBe(200);
    const json = await chatsRes.json();
    const chats = Array.isArray(json?.data) ? json.data : [];
    const withPeer = chats.find((c) => c.peer?.id === u2.user.id);
    expect(withPeer).toBeDefined();
    expect(withPeer.last_message?.content).toBe('Привет');
  });
});

// ---------- Друзья (контакты) ----------
test.describe('Друзья (контакты)', () => {
  test('добавление в друзья по username — заявка отправляется 201', async ({ request }) => {
    const a = auth(request);
    const me = await a.register();
    const friend = await a.register();
    expect(me.token).toBeDefined();
    const apiMe = api(request, me.token);
    const res = await apiMe.addContact(friend.username);
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.id).toBe(friend.user.id);
    expect(body.username).toBe(friend.username);
  });

  test('входящие заявки: получатель видит заявку, одобрение добавляет в контакты', async ({ request }) => {
    const a = auth(request);
    const me = await a.register();
    const other = await a.register();
    await api(request, me.token).addContact(other.username);
    const incomingRes = await api(request, other.token).getIncomingRequests();
    expect(incomingRes.status()).toBe(200);
    const raw = await incomingRes.json();
    const list = Array.isArray(raw) ? raw : [];
    const reqFromMe = list.find((r) => r.from_user_id === me.user.id);
    expect(reqFromMe).toBeDefined();
    const acceptRes = await api(request, other.token).acceptRequest(reqFromMe.id);
    expect(acceptRes.status()).toBe(204);
    const contactsRes = await api(request, other.token).getContacts();
    expect(contactsRes.status()).toBe(200);
    const contactsData = (await contactsRes.json()).data ?? [];
    expect(contactsData.some((c) => c.id === me.user.id)).toBe(true);
  });

  test('список контактов после добавления друга', async ({ request }) => {
    const a = auth(request);
    const me = await a.register();
    const other = await a.register();
    await api(request, me.token).addContact(other.username);
    const incRes = await api(request, other.token).getIncomingRequests();
    const raw = await incRes.json();
    const list = Array.isArray(raw) ? raw : [];
    const req = list.find((x) => x.from_user_id === me.user.id);
    if (req) await api(request, other.token).acceptRequest(req.id);
    const res = await api(request, me.token).getContacts();
    expect(res.status()).toBe(200);
    const { data } = await res.json();
    expect((data ?? []).some((c) => c.id === other.user.id)).toBe(true);
  });

  test('удаление из друзей возвращает 204, контакт исчезает из списка', async ({ request }) => {
    const a = auth(request);
    const me = await a.register();
    const other = await a.register();
    await api(request, me.token).addContact(other.username);
    const incRes = await api(request, other.token).getIncomingRequests();
    const raw = await incRes.json();
    const list = Array.isArray(raw) ? raw : [];
    const req = list.find((x) => x.from_user_id === me.user.id);
    if (req) await api(request, other.token).acceptRequest(req.id);
    const delRes = await api(request, me.token).deleteContact(other.user.id);
    expect(delRes.status()).toBe(204);
    const contactsRes = await api(request, me.token).getContacts();
    const { data } = await contactsRes.json();
    expect((data ?? []).some((c) => c.id === other.user.id)).toBe(false);
  });
});

// ---------- Сообщения ----------
test.describe('Сообщения', () => {
  test('отправка сообщения создаёт чат, получатель видит сообщение', async ({ request }) => {
    const a = auth(request);
    const u1 = await a.register();
    const u2 = await a.register();
    const api1 = api(request, u1.token);
    await api1.setPrivacyAllowAll();
    await api(request, u2.token).setPrivacyAllowAll();
    const content = `Текст ${Date.now()}`;
    const sendRes = await api1.sendMessage({ receiver_id: u2.user.id, content });
    expect(sendRes.status()).toBe(201);
    const sent = await sendRes.json();
    expect(sent.content).toBe(content);
    const getRes = await api(request, u2.token).getMessages(u1.user.id);
    expect(getRes.status()).toBe(200);
    const list = (await getRes.json()).data ?? [];
    expect(list.some((m) => m.content === content)).toBe(true);
  });

  test('ответ на сообщение (reply_to_id)', async ({ request }) => {
    const a = auth(request);
    const u1 = await a.register();
    const u2 = await a.register();
    const api1 = api(request, u1.token);
    await api1.setPrivacyAllowAll();
    await api(request, u2.token).setPrivacyAllowAll();
    const first = await api1.sendMessage({ receiver_id: u2.user.id, content: 'Первый' });
    const firstId = (await first.json()).id;
    const replyRes = await api1.sendMessage({
      receiver_id: u2.user.id,
      content: 'Ответ',
      reply_to_id: firstId,
    });
    expect(replyRes.status()).toBe(201);
    const reply = await replyRes.json();
    expect(reply.reply_to_id).toBe(firstId);
  });

  test('удаление сообщения для всех — 204, сообщение не возвращается', async ({ request }) => {
    const a = auth(request);
    const u1 = await a.register();
    const u2 = await a.register();
    const api1 = api(request, u1.token);
    await api1.setPrivacyAllowAll();
    await api(request, u2.token).setPrivacyAllowAll();
    const sendRes = await api1.sendMessage({ receiver_id: u2.user.id, content: 'Удалю это' });
    const msg = await sendRes.json();
    const delRes = await api1.deleteMessage(msg.id, false);
    expect(delRes.status()).toBe(204);
    const getRes = await api(request, u2.token).getMessages(u1.user.id);
    const list = (await getRes.json()).data ?? [];
    expect(list.some((m) => m.id === msg.id)).toBe(false);
  });

  test('пересылка сообщения: is_forwarded и forward_from_* сохраняются', async ({ request }) => {
    const a = auth(request);
    const u1 = await a.register();
    const u2 = await a.register();
    const u3 = await a.register();
    const api1 = api(request, u1.token);
    await api1.setPrivacyAllowAll();
    await api(request, u2.token).setPrivacyAllowAll();
    await api(request, u3.token).setPrivacyAllowAll();
    const orig = await api1.sendMessage({ receiver_id: u2.user.id, content: 'Оригинал' });
    const origBody = await orig.json();
    const fwdRes = await api1.sendMessage({
      receiver_id: u3.user.id,
      content: origBody.content,
      is_forwarded: true,
      forward_from_sender_id: u1.user.id,
      forward_from_display_name: u1.user.display_name || u1.username,
    });
    expect(fwdRes.status()).toBe(201);
    const fwd = await fwdRes.json();
    expect(fwd.is_forwarded).toBe(true);
    expect(fwd.forward_from_sender_id).toBe(u1.user.id);
    const listRes = await api(request, u3.token).getMessages(u1.user.id);
    const list = (await listRes.json()).data ?? [];
    const fwdInList = list.find((m) => m.id === fwd.id);
    expect(fwdInList?.is_forwarded).toBe(true);
  });
});

// ---------- Создание чата (первое сообщение), удаление, пересылка — уже покрыто выше ----------
// Отдельный тест: создание чата = первая отправка; удаление сообщения и пересылка — в блоке Сообщения.
