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
 */
export async function createChatPair(baseUrl) {
  const [u1, u2] = await Promise.all([
    createUser(baseUrl),
    createUser(baseUrl),
  ]);
  return {
    user1: { token: u1.data.token, user: u1.data.user, username: u1.data.username, password: u1.data.password },
    user2: { token: u2.data.token, user: u2.data.user, username: u2.data.username, password: u2.data.password },
  };
}
