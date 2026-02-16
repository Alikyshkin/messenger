/**
 * API-клиент для автотестов. Обёртка над fetch с поддержкой авторизации.
 */
import { authHeaders } from '../helpers.js';

export async function fetchJson(baseUrl, path, options = {}) {
  const res = await fetch(baseUrl + path, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...options.headers },
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  return { ok: res.ok, status: res.status, data };
}

/**
 * Создаёт API-клиент с привязкой к baseUrl и токену.
 */
export function createApiClient(baseUrl, token = null) {
  return {
    baseUrl,
    token,

    setToken(t) {
      this.token = t;
    },

    async request(path, options = {}) {
      const headers = this.token ? { ...authHeaders(this.token), ...options.headers } : options.headers;
      return fetchJson(this.baseUrl, path, { ...options, headers });
    },

    async get(path) {
      return this.request(path, { method: 'GET' });
    },

    async post(path, body) {
      return this.request(path, {
        method: 'POST',
        body: typeof body === 'string' ? body : JSON.stringify(body ?? {}),
      });
    },

    async patch(path, body) {
      return this.request(path, {
        method: 'PATCH',
        body: typeof body === 'string' ? body : JSON.stringify(body ?? {}),
      });
    },
  };
}
