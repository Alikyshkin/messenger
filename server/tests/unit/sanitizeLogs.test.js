/**
 * Юнит-тесты для server/utils/sanitizeLogs.js (чистые функции)
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import {
  sanitizeObject,
  sanitizeUrl,
  sanitizeHeaders,
  sanitizeBody,
  sanitizeRequest,
} from '../../utils/sanitizeLogs.js';

const MASK = '***REDACTED***';

describe('sanitizeLogs', () => {
  describe('sanitizeObject', () => {
    it('возвращает null и undefined как есть', () => {
      assert.strictEqual(sanitizeObject(null), null);
      assert.strictEqual(sanitizeObject(undefined), undefined);
    });

    it('возвращает примитивы как есть', () => {
      assert.strictEqual(sanitizeObject(42), 42);
      assert.strictEqual(sanitizeObject('hello'), 'hello');
      assert.strictEqual(sanitizeObject(true), true);
    });

    it('маскирует поле password', () => {
      assert.deepStrictEqual(sanitizeObject({ password: 'secret' }), { password: MASK });
    });

    it('маскирует password_hash, token, authorization, apiKey и др.', () => {
      assert.deepStrictEqual(sanitizeObject({ password_hash: 'x' }), { password_hash: MASK });
      assert.deepStrictEqual(sanitizeObject({ token: 'jwt' }), { token: MASK });
      assert.deepStrictEqual(sanitizeObject({ authorization: 'Bearer x' }), { authorization: MASK });
      assert.deepStrictEqual(sanitizeObject({ apiKey: 'key123' }), { apiKey: MASK });
      assert.deepStrictEqual(sanitizeObject({ refresh_token: 'rt' }), { refresh_token: MASK });
    });

    it('не трогает обычные поля', () => {
      assert.deepStrictEqual(sanitizeObject({ name: 'alice', count: 1 }), { name: 'alice', count: 1 });
    });

    it('рекурсивно санитизирует вложенные объекты', () => {
      const input = { user: { password: 'p', login: 'a' } };
      assert.deepStrictEqual(sanitizeObject(input), { user: { password: MASK, login: 'a' } });
    });

    it('санитизирует элементы массива', () => {
      const input = [{ password: 'p1' }, { name: 'ok' }];
      assert.deepStrictEqual(sanitizeObject(input), [{ password: MASK }, { name: 'ok' }]);
    });

    it('ограничивает глубину maxDepth', () => {
      const deep = { a: { b: { c: { d: { e: { f: 1 } } } } } };
      const out = sanitizeObject(deep, 0, 3);
      assert.strictEqual(out.a.b.c.d, '[Max depth reached]');
    });
  });

  describe('sanitizeUrl', () => {
    it('возвращает null/undefined и не-строку как есть', () => {
      assert.strictEqual(sanitizeUrl(null), null);
      assert.strictEqual(sanitizeUrl(undefined), undefined);
      assert.strictEqual(sanitizeUrl(123), 123);
    });

    it('убирает чувствительные query-параметры', () => {
      const url = '/api?token=secret&page=1';
      assert.ok(sanitizeUrl(url).includes('/api'));
      assert.ok(sanitizeUrl(url).includes(MASK));
      assert.ok(!sanitizeUrl(url).includes('secret'));
    });

    it('оставляет pathname и безопасные параметры', () => {
      const out = sanitizeUrl('/path?foo=bar');
      assert.ok(out.includes('/path'));
      assert.ok(out.includes('foo=bar'));
    });
  });

  describe('sanitizeHeaders', () => {
    it('возвращает не-объект как есть', () => {
      assert.strictEqual(sanitizeHeaders(null), null);
      assert.strictEqual(sanitizeHeaders('x'), 'x');
    });

    it('маскирует authorization, cookie, x-api-key', () => {
      const headers = {
        'authorization': 'Bearer xxx',
        'cookie': 'session=abc',
        'x-api-key': 'key',
        'content-type': 'application/json',
      };
      const out = sanitizeHeaders(headers);
      assert.strictEqual(out['authorization'], MASK);
      assert.strictEqual(out['cookie'], MASK);
      assert.strictEqual(out['x-api-key'], MASK);
      assert.strictEqual(out['content-type'], 'application/json');
    });
  });

  describe('sanitizeBody', () => {
    it('возвращает null/undefined как есть', () => {
      assert.strictEqual(sanitizeBody(null), null);
      assert.strictEqual(sanitizeBody(undefined), undefined);
    });

    it('санитизирует объект', () => {
      assert.deepStrictEqual(sanitizeBody({ password: 'x' }), { password: MASK });
    });

    it('санитизирует JSON-строку', () => {
      const out = sanitizeBody(JSON.stringify({ token: 'secret' }));
      assert.ok(out.includes(MASK));
      const parsed = JSON.parse(out);
      assert.strictEqual(parsed.token, MASK);
    });

    it('маскирует строку с password/token если не JSON', () => {
      assert.strictEqual(sanitizeBody('body with password=secret'), MASK);
    });
  });

  describe('sanitizeRequest', () => {
    it('возвращает объект с method, url, headers, body, query, params', () => {
      const req = {
        method: 'POST',
        url: '/login?token=x',
        headers: { authorization: 'Bearer y' },
        body: { password: 'p' },
        query: { redirect: '/home' },
        params: {},
        ip: '127.0.0.1',
        connection: { remoteAddress: '127.0.0.1' },
        get: (name) => (name === 'user-agent' ? 'Mozilla' : undefined),
      };
      const out = sanitizeRequest(req);
      assert.strictEqual(out.method, 'POST');
      assert.ok(out.url.includes('/login'));
      assert.strictEqual(out.headers.authorization, MASK);
      assert.strictEqual(out.body.password, MASK);
      assert.deepStrictEqual(out.query, { redirect: '/home' });
      assert.strictEqual(out.ip, '127.0.0.1');
      assert.strictEqual(out.userAgent, 'Mozilla');
    });
  });
});
