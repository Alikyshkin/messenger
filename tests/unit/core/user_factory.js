/**
 * Фабрика тестовых пользователей. Регистрация и логин.
 */
import { register, login } from '../helpers.js';

let userCounter = 0;

/**
 * Создаёт уникальное имя пользователя для тестов.
 */
export function uniqueUsername(prefix = 'user') {
  return `${prefix}_${Date.now()}_${++userCounter}`;
}

/**
 * Регистрирует нового пользователя.
 * @returns {{ status, data: { token, user } }}
 */
export async function createUser(baseUrl, overrides = {}) {
  const username = overrides.username ?? uniqueUsername();
  const password = overrides.password ?? 'TestPass123!';
  const displayName = overrides.displayName ?? `Test User ${userCounter}`;
  const email = overrides.email;

  const { status, data } = await register(baseUrl, {
    username,
    password,
    displayName,
    ...(email != null && { email }),
  });

  if (status !== 201) {
    throw new Error(`Failed to register user: ${status} ${JSON.stringify(data)}`);
  }

  return {
    status,
    data: {
      token: data.token,
      user: data.user,
      username,
      password,
    },
  };
}

/**
 * Логинит существующего пользователя.
 */
export async function loginUser(baseUrl, username, password) {
  const { status, data } = await login(baseUrl, username, password);
  if (status !== 200) {
    throw new Error(`Failed to login: ${status} ${JSON.stringify(data)}`);
  }
  return { token: data.token, user: data.user };
}

/**
 * Создаёт двух пользователей для тестов чата (отправитель и получатель).
 * Устанавливает взаимные контакты для корректной работы сообщений и звонков.
 */
export async function createChatPair(baseUrl) {
  const [u1, u2] = await Promise.all([
    createUser(baseUrl),
    createUser(baseUrl),
  ]);
  const user1 = { token: u1.data.token, user: u1.data.user, username: u1.data.username, password: u1.data.password };
  const user2 = { token: u2.data.token, user: u2.data.user, username: u2.data.username, password: u2.data.password };

  const { fetchJson, authHeaders } = await import('../helpers.js');

  await fetchJson(baseUrl, '/contacts', {
    method: 'POST',
    headers: authHeaders(user1.token),
    body: JSON.stringify({ username: user2.username }),
  });
  await fetchJson(baseUrl, '/contacts', {
    method: 'POST',
    headers: authHeaders(user2.token),
    body: JSON.stringify({ username: user1.username }),
  });
  const incoming2 = await fetchJson(baseUrl, '/contacts/requests/incoming', {
    headers: authHeaders(user2.token),
  });
  for (const r of incoming2.data) {
    await fetchJson(baseUrl, `/contacts/requests/${r.id}/accept`, {
      method: 'POST',
      headers: authHeaders(user2.token),
    });
  }
  const incoming1 = await fetchJson(baseUrl, '/contacts/requests/incoming', {
    headers: authHeaders(user1.token),
  });
  for (const r of incoming1.data) {
    await fetchJson(baseUrl, `/contacts/requests/${r.id}/accept`, {
      method: 'POST',
      headers: authHeaders(user1.token),
    });
  }

  return { user1, user2 };
}
