import request from 'supertest';
import Database from 'better-sqlite3';
import { existsSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const testDbPath = join(__dirname, '../test.db');

let app;
let server;
let user1Token;
let user2Token;
let user1Id;
let user2Id;

beforeAll(async () => {
  // Очистка тестовой БД
  if (existsSync(testDbPath)) {
    unlinkSync(testDbPath);
  }

  // Создаём тестовую БД с полной схемой
  const db = new Database(testDbPath);
  db.exec(`
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      display_name TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      is_online INTEGER DEFAULT 0,
      last_seen DATETIME
    );
    
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sender_id INTEGER NOT NULL,
      receiver_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      read_at DATETIME,
      attachment_path TEXT,
      attachment_filename TEXT,
      message_type TEXT DEFAULT 'text',
      FOREIGN KEY (sender_id) REFERENCES users(id),
      FOREIGN KEY (receiver_id) REFERENCES users(id)
    );
    
    CREATE TABLE contacts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      contact_id INTEGER NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, contact_id),
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (contact_id) REFERENCES users(id)
    );
  `);

  // Создаём тестовых пользователей
  const passwordHash = await bcrypt.hash('password123', 10);
  const user1 = db.prepare('INSERT INTO users (username, password_hash, display_name) VALUES (?, ?, ?)')
    .run('user1', passwordHash, 'User 1');
  const user2 = db.prepare('INSERT INTO users (username, password_hash, display_name) VALUES (?, ?, ?)')
    .run('user2', passwordHash, 'User 2');
  
  user1Id = user1.lastInsertRowid;
  user2Id = user2.lastInsertRowid;

  // Добавляем контакты
  db.prepare('INSERT INTO contacts (user_id, contact_id) VALUES (?, ?)').run(user1Id, user2Id);
  db.prepare('INSERT INTO contacts (user_id, contact_id) VALUES (?, ?)').run(user2Id, user1Id);

  db.close();

  // Настраиваем окружение
  process.env.MESSENGER_DB_PATH = testDbPath;
  process.env.JWT_SECRET = 'test-secret-key';
  process.env.NODE_ENV = 'test';

  // Импортируем приложение
  const module = await import('../index.js');
  app = module.default;
  server = module.server;

  // Получаем токены
  const login1 = await request(app)
    .post('/auth/login')
    .send({ username: 'user1', password: 'password123' });
  user1Token = login1.body.token;

  const login2 = await request(app)
    .post('/auth/login')
    .send({ username: 'user2', password: 'password123' });
  user2Token = login2.body.token;
});

afterAll(async () => {
  if (server) {
    await new Promise((resolve) => {
      server.close(resolve);
    });
  }
  if (existsSync(testDbPath)) {
    unlinkSync(testDbPath);
  }
});

describe('Messages API', () => {
  let messageId;

  describe('POST /messages', () => {
    it('должен отправить сообщение', async () => {
      const response = await request(app)
        .post('/messages')
        .set('Authorization', `Bearer ${user1Token}`)
        .send({
          receiver_id: user2Id,
          content: 'Test message',
        })
        .expect(201);

      expect(response.body).toHaveProperty('id');
      expect(response.body.content).toBe('Test message');
      expect(response.body.sender_id).toBe(user1Id);
      expect(response.body.receiver_id).toBe(user2Id);
      
      messageId = response.body.id;
    });

    it('должен вернуть ошибку без receiver_id', async () => {
      await request(app)
        .post('/messages')
        .set('Authorization', `Bearer ${user1Token}`)
        .send({
          content: 'Test message',
        })
        .expect(400);
    });

    it('должен вернуть ошибку без контента и файла', async () => {
      await request(app)
        .post('/messages')
        .set('Authorization', `Bearer ${user1Token}`)
        .send({
          receiver_id: user2Id,
        })
        .expect(400);
    });
  });

  describe('GET /messages/:peerId', () => {
    it('должен получить список сообщений', async () => {
      const response = await request(app)
        .get(`/messages/${user2Id}`)
        .set('Authorization', `Bearer ${user1Token}`)
        .expect(200);

      expect(response.body).toHaveProperty('data');
      expect(response.body).toHaveProperty('pagination');
      expect(Array.isArray(response.body.data)).toBe(true);
      expect(response.body.data.length).toBeGreaterThan(0);
    });

    it('должен поддерживать пагинацию', async () => {
      const response = await request(app)
        .get(`/messages/${user2Id}?limit=1`)
        .set('Authorization', `Bearer ${user1Token}`)
        .expect(200);

      expect(response.body.data.length).toBeLessThanOrEqual(1);
      expect(response.body.pagination).toHaveProperty('limit');
    });
  });

  describe('DELETE /messages/:messageId', () => {
    it('должен удалить сообщение', async () => {
      await request(app)
        .delete(`/messages/${messageId}`)
        .set('Authorization', `Bearer ${user1Token}`)
        .expect(204);
    });

    it('должен вернуть 404 для несуществующего сообщения', async () => {
      await request(app)
        .delete('/messages/99999')
        .set('Authorization', `Bearer ${user1Token}`)
        .expect(404);
    });
  });
});
