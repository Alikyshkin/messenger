/**
 * Юнит-тесты middleware apiVersioning: заголовок Accept, query, validateApiVersion.
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import { apiVersioning, validateApiVersion, isVersionSupported } from '../../server/middleware/apiVersioning.js';

describe('isVersionSupported', () => {
  it('поддерживает v1', () => {
    assert.strictEqual(isVersionSupported('v1'), true);
  });

  it('не поддерживает неизвестные версии', () => {
    assert.strictEqual(isVersionSupported('v2'), false);
    assert.strictEqual(isVersionSupported('v0'), false);
  });
});

describe('apiVersioning middleware', () => {
  function reqResNext(accept, query = {}) {
    const req = { get: (name) => (name === 'Accept' ? accept : undefined), query };
    const res = { setHeader: () => {} };
    let capturedVersion;
    const next = () => { capturedVersion = req.apiVersion; };
    return { req, res, next: () => next(), getVersion: () => req.apiVersion };
  }

  it('устанавливает v1 по умолчанию', (_, done) => {
    const req = { get: () => '', query: {} };
    const res = { setHeader: () => {} };
    apiVersioning(req, res, () => {
      assert.strictEqual(req.apiVersion, 'v1');
      done();
    });
  });

  it('извлекает версию из Accept version=N', (_, done) => {
    const req = { get: (n) => (n === 'Accept' ? 'application/json; version=1' : undefined), query: {} };
    const res = { setHeader: () => {} };
    apiVersioning(req, res, () => {
      assert.strictEqual(req.apiVersion, 'v1');
      done();
    });
  });

  it('извлекает версию из query api_version', (_, done) => {
    const req = { get: () => '', query: { api_version: '1' } };
    const res = { setHeader: () => {} };
    apiVersioning(req, res, () => {
      assert.strictEqual(req.apiVersion, 'v1');
      done();
    });
  });
});

describe('validateApiVersion middleware', () => {
  it('пропускает v1', (_, done) => {
    const req = { apiVersion: 'v1' };
    validateApiVersion(req, {}, () => done());
  });

  it('возвращает 400 для неподдерживаемой версии', (_, done) => {
    const req = { apiVersion: 'v2' };
    const res = {
      statusCode: undefined,
      body: undefined,
      status(code) { this.statusCode = code; return this; },
      json(body) {
        this.body = body;
        assert.strictEqual(this.statusCode, 400);
        assert.ok(body?.supportedVersions?.includes('v1'));
        done();
        return this;
      },
    };
    validateApiVersion(req, res, () => {});
  });
});
