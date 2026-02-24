import request from 'supertest';
import Database from 'better-sqlite3';
import { existsSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const testDbPath = join(__dirname, '../test.db');

// Очистка тестовой БД перед запуском
if (existsSync(testDbPath)) {
  unlinkSync(testDbPath);
}

// Создаём тестовую БД
const db = new Database(testDbPath);
db.exec(`
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
`);

// Импортируем приложение после настройки БД
process.env.MESSENGER_DB_PATH = testDbPath;
process.env.JWT_SECRET = 'test-secret-key';
process.env.NODE_ENV = 'test';

let app;
let server;

beforeAll(async () => {
  const module = await import('../index.js');
  app = module.app;
  server = module.server;
});

afterAll(async () => {
  if (server) {
    await new Promise((resolve) => {
      server.close(resolve);
    });
  }
  db.close();
  if (existsSync(testDbPath)) {
    unlinkSync(testDbPath);
  }
});

describe('Auth API', () => {
  let authToken;
  let userId;

  describe('POST /auth/register', () => {
    it('должен зарегистрировать нового пользователя', async () => {
      const response = await request(app)
        .post('/auth/register')
        .send({
          username: 'testuser',
          password: 'password123',
          displayName: 'Test User',
        })
        .expect(201);

      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      expect(response.body.user.username).toBe('testuser');
      expect(response.body.user.display_name).toBe('Test User');
      
      authToken = response.body.token;
      userId = response.body.user.id;
    });

    it('должен вернуть ошибку при дублировании username', async () => {
      await request(app)
        .post('/auth/register')
        .send({
          username: 'testuser',
          password: 'password123',
        })
        .expect(409);
    });

    it('должен вернуть ошибку при отсутствии обязательных полей', async () => {
      await request(app)
        .post('/auth/register')
        .send({
          username: 'testuser2',
        })
        .expect(400);
    });

    it('должен вернуть ошибку при коротком пароле', async () => {
      await request(app)
        .post('/auth/register')
        .send({
          username: 'testuser3',
          password: '123',
        })
        .expect(400);
    });
  });

  describe('POST /auth/login', () => {
    it('должен успешно войти с правильными credentials', async () => {
      const response = await request(app)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'password123',
        })
        .expect(200);

      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      expect(response.body.user.username).toBe('testuser');
    });

    it('должен вернуть ошибку при неправильном пароле', async () => {
      await request(app)
        .post('/auth/login')
        .send({
          username: 'testuser',
          password: 'wrongpassword',
        })
        .expect(401);
    });

    it('должен вернуть ошибку при несуществующем пользователе', async () => {
      await request(app)
        .post('/auth/login')
        .send({
          username: 'nonexistent',
          password: 'password123',
        })
        .expect(401);
    });
  });

  describe('GET /users/me', () => {
    it('должен вернуть информацию о текущем пользователе', async () => {
      const response = await request(app)
        .get('/users/me')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body.username).toBe('testuser');
      expect(response.body.id).toBe(userId);
    });

    it('должен вернуть 401 без токена', async () => {
      await request(app)
        .get('/users/me')
        .expect(401);
    });

    it('должен вернуть 401 с невалидным токеном', async () => {
      await request(app)
        .get('/users/me')
        .set('Authorization', 'Bearer invalid-token')
        .expect(401);
    });
  });
});
