/**
 * Хелперы для тестов. Сервер должен быть запущен с NODE_ENV=test и MESSENGER_DB_PATH=:memory:
 * Тесты не попадают в прод: они в папке tests/ и запускаются только по npm test.
 */

export async function fetchJson(baseUrl, path, options = {}) {
  const res = await fetch(baseUrl + path, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...options.headers },
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  return { ok: res.ok, status: res.status, data };
}

export function register(baseUrl, { username = 'user1', password = 'pass123', displayName, email } = {}) {
  return fetchJson(baseUrl, '/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      username,
      password,
      ...(displayName != null && { displayName }),
      ...(email != null && { email }),
    }),
  });
}

export function login(baseUrl, username, password) {
  return fetchJson(baseUrl, '/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

export function authHeaders(token) {
  return { Authorization: `Bearer ${token}` };
}
