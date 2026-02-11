import { validate, registerSchema, loginSchema, sendMessageSchema } from '../middleware/validation.js';

describe('Validation Schemas', () => {
  describe('registerSchema', () => {
    it('должен валидировать корректные данные', () => {
      const validData = {
        username: 'testuser',
        password: 'password123',
        displayName: 'Test User',
        email: 'test@example.com',
      };
      
      const { error } = registerSchema.validate(validData);
      expect(error).toBeUndefined();
    });

    it('должен отклонять короткий username', () => {
      const invalidData = {
        username: 'ab',
        password: 'password123',
      };
      
      const { error } = registerSchema.validate(invalidData);
      expect(error).toBeDefined();
      expect(error.details[0].path).toContain('username');
    });

    it('должен отклонять короткий пароль', () => {
      const invalidData = {
        username: 'testuser',
        password: '123',
      };
      
      const { error } = registerSchema.validate(invalidData);
      expect(error).toBeDefined();
      expect(error.details[0].path).toContain('password');
    });

    it('должен отклонять невалидный email', () => {
      const invalidData = {
        username: 'testuser',
        password: 'password123',
        email: 'invalid-email',
      };
      
      const { error } = registerSchema.validate(invalidData);
      expect(error).toBeDefined();
      expect(error.details[0].path).toContain('email');
    });
  });

  describe('loginSchema', () => {
    it('должен валидировать корректные данные', () => {
      const validData = {
        username: 'testuser',
        password: 'password123',
      };
      
      const { error } = loginSchema.validate(validData);
      expect(error).toBeUndefined();
    });

    it('должен требовать username', () => {
      const invalidData = {
        password: 'password123',
      };
      
      const { error } = loginSchema.validate(invalidData);
      expect(error).toBeDefined();
    });

    it('должен требовать password', () => {
      const invalidData = {
        username: 'testuser',
      };
      
      const { error } = loginSchema.validate(invalidData);
      expect(error).toBeDefined();
    });
  });

  describe('sendMessageSchema', () => {
    it('должен валидировать корректные данные', () => {
      const validData = {
        receiver_id: 1,
        content: 'Test message',
      };
      
      const { error } = sendMessageSchema.validate(validData);
      expect(error).toBeUndefined();
    });

    it('должен требовать receiver_id', () => {
      const invalidData = {
        content: 'Test message',
      };
      
      const { error } = sendMessageSchema.validate(invalidData);
      expect(error).toBeDefined();
      expect(error.details[0].path).toContain('receiver_id');
    });

    it('должен отклонять слишком длинный контент', () => {
      const invalidData = {
        receiver_id: 1,
        content: 'a'.repeat(10001),
      };
      
      const { error } = sendMessageSchema.validate(invalidData);
      expect(error).toBeDefined();
      expect(error.details[0].path).toContain('content');
    });
  });
});
