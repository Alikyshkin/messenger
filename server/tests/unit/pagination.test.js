/**
 * Юнит-тесты middleware pagination: граничные значения limit/offset.
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import { paginationSchema, createPaginationMeta } from '../../middleware/pagination.js';
import { PAGINATION } from '../../config/constants.js';

describe('paginationSchema', () => {
  it('принимает валидные limit и offset', () => {
    const { error, value } = paginationSchema.validate({ limit: 50, offset: 0 });
    assert.strictEqual(error, undefined);
    assert.strictEqual(value.limit, 50);
    assert.strictEqual(value.offset, 0);
  });

  it('подставляет default limit и offset при пустом query', () => {
    const { error, value } = paginationSchema.validate({});
    assert.strictEqual(error, undefined);
    assert.strictEqual(value.limit, PAGINATION.DEFAULT_LIMIT);
    assert.strictEqual(value.offset, 0);
  });

  it('отклоняет limit меньше MIN_LIMIT', () => {
    const { error } = paginationSchema.validate({ limit: 0 });
    assert.ok(error);
  });

  it('отклоняет limit больше MAX_LIMIT', () => {
    const { error } = paginationSchema.validate({ limit: PAGINATION.MAX_LIMIT + 1 });
    assert.ok(error);
  });

  it('отклоняет отрицательный offset', () => {
    const { error } = paginationSchema.validate({ offset: -1 });
    assert.ok(error);
  });

  it('принимает граничные limit', () => {
    const { error: e1 } = paginationSchema.validate({ limit: PAGINATION.MIN_LIMIT });
    assert.strictEqual(e1, undefined);
    const { error: e2 } = paginationSchema.validate({ limit: PAGINATION.MAX_LIMIT });
    assert.strictEqual(e2, undefined);
  });
});

describe('createPaginationMeta', () => {
  it('считает hasMore и totalPages', () => {
    const meta = createPaginationMeta(100, 10, 0);
    assert.strictEqual(meta.total, 100);
    assert.strictEqual(meta.limit, 10);
    assert.strictEqual(meta.offset, 0);
    assert.strictEqual(meta.hasMore, true);
    assert.strictEqual(meta.page, 1);
    assert.strictEqual(meta.totalPages, 10);
  });

  it('последняя страница: hasMore false', () => {
    const meta = createPaginationMeta(25, 10, 20);
    assert.strictEqual(meta.hasMore, false);
    assert.strictEqual(meta.page, 3);
    assert.strictEqual(meta.totalPages, 3);
  });
});
