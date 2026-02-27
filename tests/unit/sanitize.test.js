/**
 * Юнит-тесты middleware sanitize: граничные и опасные входные данные.
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import { sanitizeHtml, escapeHtml, sanitizeText } from '../../server/middleware/sanitize.js';

describe('sanitizeHtml', () => {
  it('возвращает пустую строку для не-строки', () => {
    assert.strictEqual(sanitizeHtml(null), '');
    assert.strictEqual(sanitizeHtml(undefined), '');
    assert.strictEqual(sanitizeHtml(123), '');
  });

  it('удаляет script-теги', () => {
    const input = '<p>Hello</p><script>alert(1)</script>';
    const out = sanitizeHtml(input);
    assert.ok(!out.includes('<script'));
    assert.ok(!out.includes('alert'));
  });

  it('оставляет разрешённые теги', () => {
    const input = '<b>bold</b> <i>italic</i> <br/>';
    const out = sanitizeHtml(input);
    assert.ok(out.includes('bold'));
    assert.ok(out.includes('italic'));
  });

  it('удаляет onclick и другие атрибуты', () => {
    const input = '<span onclick="alert(1)">x</span>';
    const out = sanitizeHtml(input);
    assert.ok(!out.includes('onclick'));
  });
});

describe('escapeHtml', () => {
  it('возвращает пустую строку для не-строки', () => {
    assert.strictEqual(escapeHtml(null), '');
    assert.strictEqual(escapeHtml(undefined), '');
  });

  it('экранирует & < > " \'', () => {
    assert.strictEqual(escapeHtml('&'), '&amp;');
    assert.strictEqual(escapeHtml('<'), '&lt;');
    assert.strictEqual(escapeHtml('>'), '&gt;');
    assert.strictEqual(escapeHtml('"'), '&quot;');
    assert.strictEqual(escapeHtml("'"), '&#039;');
  });

  it('не трогает безопасные символы', () => {
    assert.strictEqual(escapeHtml('Hello'), 'Hello');
  });
});

describe('sanitizeText', () => {
  it('возвращает пустую строку для не-строки', () => {
    assert.strictEqual(sanitizeText(null), '');
    assert.strictEqual(sanitizeText(undefined), '');
  });

  it('удаляет управляющие символы', () => {
    const input = 'Hello\x00World\x07';
    assert.strictEqual(sanitizeText(input), 'HelloWorld');
  });

  it('оставляет перевод строки и табуляцию', () => {
    const input = 'a\nb\tc';
    assert.strictEqual(sanitizeText(input), 'a\nb\tc');
  });

  it('обрезает пробелы по краям', () => {
    assert.strictEqual(sanitizeText('  x  '), 'x');
  });
});
