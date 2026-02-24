/**
 * Юнит-тесты для server/cipher.js (чистые функции encrypt/decrypt/decryptIfLegacy)
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { encrypt, decrypt, decryptIfLegacy } from '../../cipher.js';

const PREFIX = 'enc:';

describe('cipher', () => {
  const originalEnv = process.env.ENCRYPTION_KEY;

  before(() => {
    process.env.ENCRYPTION_KEY = 'test-encryption-key-min-16-chars';
  });

  after(() => {
    if (originalEnv !== undefined) {
      process.env.ENCRYPTION_KEY = originalEnv;
    } else {
      delete process.env.ENCRYPTION_KEY;
    }
  });

  describe('decrypt', () => {
    it('возвращает не-строку как есть', () => {
      assert.strictEqual(decrypt(null), null);
      assert.strictEqual(decrypt(undefined), undefined);
      assert.strictEqual(decrypt(123), 123);
    });

    it('возвращает строку без префикса enc: как есть', () => {
      assert.strictEqual(decrypt('plain text'), 'plain text');
      assert.strictEqual(decrypt(''), '');
    });

    it('расшифровывает зашифрованную строку (roundtrip)', () => {
      const plain = 'secret message';
      const encrypted = encrypt(plain);
      assert.ok(encrypted.startsWith(PREFIX));
      assert.notStrictEqual(encrypted, plain);
      assert.strictEqual(decrypt(encrypted), plain);
    });

    it('при невалидном base64/формате возвращает ciphertext', () => {
      const invalid = PREFIX + 'not-valid-base64!!!';
      assert.strictEqual(decrypt(invalid), invalid);
    });
  });

  describe('decryptIfLegacy', () => {
    it('возвращает не-строку как есть', () => {
      assert.strictEqual(decryptIfLegacy(null), null);
      assert.strictEqual(decryptIfLegacy(123), 123);
    });

    it('возвращает строку без префикса enc: как есть', () => {
      assert.strictEqual(decryptIfLegacy('e2ee payload'), 'e2ee payload');
    });

    it('расшифровывает legacy enc: строку', () => {
      const plain = 'legacy content';
      const encrypted = encrypt(plain);
      assert.strictEqual(decryptIfLegacy(encrypted), plain);
    });
  });

  describe('encrypt', () => {
    it('без ENCRYPTION_KEY возвращает plaintext', () => {
      const key = process.env.ENCRYPTION_KEY;
      delete process.env.ENCRYPTION_KEY;
      try {
        assert.strictEqual(encrypt('hello'), 'hello');
      } finally {
        if (key) process.env.ENCRYPTION_KEY = key;
      }
    });

    it('с ключом возвращает строку с префиксом enc:', () => {
      const out = encrypt('data');
      assert.ok(out.startsWith(PREFIX));
      assert.ok(out.length > PREFIX.length);
    });
  });
});
