// @ts-check
/**
 * Общие хелперы для Playwright-тестов (API и E2E): уникальные имена, пароль, авторизация.
 */
const PASSWORD = 'TestPass123!';

function unique(prefix = 'user') {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
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

export { PASSWORD, unique, auth };
