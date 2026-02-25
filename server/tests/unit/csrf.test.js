/**
 * Юнит-тесты middleware csrf: GET/HEAD/OPTIONS пропускаются, Bearer пропускается.
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import { csrfProtect } from '../../middleware/csrf.js';

describe('csrfProtect', () => {
  it('пропускает GET без вызова next с ошибкой', (_, done) => {
    const mw = csrfProtect();
    const req = { method: 'GET' };
    const res = {};
    let nextCalled = false;
    mw(req, res, () => {
      nextCalled = true;
      done();
    });
    assert.strictEqual(nextCalled, true);
  });

  it('пропускает HEAD', (_, done) => {
    const mw = csrfProtect();
    const req = { method: 'HEAD' };
    mw(req, {}, () => done());
  });

  it('пропускает OPTIONS', (_, done) => {
    const mw = csrfProtect();
    const req = { method: 'OPTIONS' };
    mw(req, {}, () => done());
  });

  it('пропускает запрос с Authorization: Bearer ...', (_, done) => {
    const mw = csrfProtect();
    const req = { method: 'POST', headers: { authorization: 'Bearer some-jwt' } };
    mw(req, {}, () => done());
  });

  it('пропускает запрос с authorization в нижнем регистре', (_, done) => {
    const mw = csrfProtect();
    const req = { method: 'POST', headers: { authorization: 'Bearer x' } };
    mw(req, {}, () => done());
  });
});
