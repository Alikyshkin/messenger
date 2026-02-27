// @ts-check
/**
 * Общие хелперы для Playwright-тестов (API и E2E): уникальные имена, пароль, авторизация.
 */
const PASSWORD = 'TestPass123!';

let _counter = 0;
function unique(prefix = 'user') {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}_${(++_counter).toString(36)}`;
}

/**
 * @param {import('@playwright/test').APIRequestContext} request
 */
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

/**
 * Создать двух зарегистрированных пользователей с взаимными контактами через API.
 * @param {import('@playwright/test').APIRequestContext} request - request context привязанный к серверу
 * @param {string} [serverBase] - URL сервера (если отличается от request base)
 * @returns {Promise<{user1: {username: string, token: string, id: number}, user2: {username: string, token: string, id: number}}>}
 */
async function createContactPair(request, serverBase) {
  const base = serverBase || '';
  const u1name = unique();
  const u2name = unique();
  const r1 = await request.post(`${base}/auth/register`, { data: { username: u1name, password: PASSWORD, displayName: `User ${u1name}` } });
  const b1 = await r1.json();
  const r2 = await request.post(`${base}/auth/register`, { data: { username: u2name, password: PASSWORD, displayName: `User ${u2name}` } });
  const b2 = await r2.json();

  const h1 = { Authorization: `Bearer ${b1.token}` };
  const h2 = { Authorization: `Bearer ${b2.token}` };

  await request.post(`${base}/contacts`, { headers: h1, data: { username: u2name } });
  await request.post(`${base}/contacts`, { headers: h2, data: { username: u1name } });

  const inc2Raw = await (await request.get(`${base}/contacts/requests/incoming`, { headers: h2 })).json();
  const inc2 = Array.isArray(inc2Raw) ? inc2Raw : [];
  for (const r of inc2) {
    await request.post(`${base}/contacts/requests/${r.id}/accept`, { headers: h2 });
  }
  const inc1Raw = await (await request.get(`${base}/contacts/requests/incoming`, { headers: h1 })).json();
  const inc1 = Array.isArray(inc1Raw) ? inc1Raw : [];
  for (const r of inc1) {
    await request.post(`${base}/contacts/requests/${r.id}/accept`, { headers: h1 });
  }

  return {
    user1: { username: u1name, token: b1.token, id: b1.user.id },
    user2: { username: u2name, token: b2.token, id: b2.user.id },
  };
}

export { PASSWORD, unique, auth, createContactPair };
