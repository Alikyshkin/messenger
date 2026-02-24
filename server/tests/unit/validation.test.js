/**
 * Unit-тесты схем валидации (Joi). Перенесено из __tests__/validation.test.js.
 */
import { describe, it } from 'node:test';
import { strict as assert } from 'node:assert';
import { registerSchema, loginSchema, sendMessageSchema } from '../../middleware/validation.js';

describe('Validation Schemas', () => {
  describe('registerSchema', () => {
    const strongPassword = 'MyP@ssw0rd!xY';

    it('должен валидировать корректные данные', () => {
      const validData = {
        username: 'testuser',
        password: strongPassword,
        displayName: 'Test User',
        email: 'test@example.com',
      };
      const { error } = registerSchema.validate(validData);
      assert.strictEqual(error, undefined);
    });

    it('должен отклонять короткий username', () => {
      const invalidData = { username: 'ab', password: strongPassword };
      const { error } = registerSchema.validate(invalidData);
      assert.ok(error);
      assert.ok(error.details[0].path.includes('username'));
    });

    it('должен отклонять короткий пароль', () => {
      const invalidData = { username: 'testuser', password: '123' };
      const { error } = registerSchema.validate(invalidData);
      assert.ok(error);
      assert.ok(error.details[0].path.includes('password'));
    });

    it('должен отклонять невалидный email', () => {
      const invalidData = {
        username: 'testuser',
        password: strongPassword,
        email: 'invalid-email',
      };
      const { error } = registerSchema.validate(invalidData);
      assert.ok(error);
      const emailError = error.details.find((d) => d.path.includes('email'));
      assert.ok(emailError, 'expected validation error for email');
    });
  });

  describe('loginSchema', () => {
    it('должен валидировать корректные данные', () => {
      const validData = { username: 'testuser', password: 'password123' };
      const { error } = loginSchema.validate(validData);
      assert.strictEqual(error, undefined);
    });

    it('должен требовать username', () => {
      const invalidData = { password: 'password123' };
      const { error } = loginSchema.validate(invalidData);
      assert.ok(error);
    });

    it('должен требовать password', () => {
      const invalidData = { username: 'testuser' };
      const { error } = loginSchema.validate(invalidData);
      assert.ok(error);
    });
  });

  describe('sendMessageSchema', () => {
    it('должен валидировать корректные данные', () => {
      const validData = { receiver_id: 1, content: 'Test message' };
      const { error } = sendMessageSchema.validate(validData);
      assert.strictEqual(error, undefined);
    });

    it('должен требовать receiver_id', () => {
      const invalidData = { content: 'Test message' };
      const { error } = sendMessageSchema.validate(invalidData);
      assert.ok(error);
      assert.ok(error.details[0].path.includes('receiver_id'));
    });

    it('должен отклонять слишком длинный контент', () => {
      const invalidData = { receiver_id: 1, content: 'a'.repeat(10001) };
      const { error } = sendMessageSchema.validate(invalidData);
      assert.ok(error);
      assert.ok(error.details[0].path.includes('content'));
    });
  });
});
