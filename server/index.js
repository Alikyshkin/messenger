import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import compression from 'compression';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { verifyToken } from './auth.js';
import { clients, broadcastToUser } from './realtime.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { log } from './utils/logger.js';

import authRoutes from './routes/auth.js';
import contactsRoutes from './routes/contacts.js';
import messagesRoutes from './routes/messages.js';
import usersRoutes from './routes/users.js';
import chatsRoutes from './routes/chats.js';
import groupsRoutes from './routes/groups.js';
import pollsRoutes from './routes/polls.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const uploadsDir = join(__dirname, 'uploads');
const publicDir = join(__dirname, 'public');
if (!existsSync(uploadsDir)) mkdirSync(uploadsDir, { recursive: true });
if (!existsSync(publicDir)) mkdirSync(publicDir, { recursive: true });

const app = express();
const server = createServer(app);

// CORS настройка
const allowedOrigins = process.env.CORS_ORIGINS 
  ? process.env.CORS_ORIGINS.split(',').map(origin => origin.trim())
  : ['http://localhost:3000', 'http://localhost:8080', 'http://127.0.0.1:3000', 'http://127.0.0.1:8080'];

app.use(cors({
  origin: (origin, callback) => {
    // Разрешаем запросы без origin (например, мобильные приложения, Postman)
    if (!origin) return callback(null, true);
    
    if (allowedOrigins.includes(origin) || process.env.NODE_ENV === 'development') {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  exposedHeaders: ['Content-Length', 'X-Foo', 'X-Bar'],
  maxAge: 86400, // 24 часа
}));

// Сжатие ответов (gzip/brotli)
app.use(compression({
  filter: (req, res) => {
    // Сжимаем только если клиент поддерживает сжатие
    if (req.headers['x-no-compression']) {
      return false;
    }
    // Используем стандартный фильтр compression
    return compression.filter(req, res);
  },
  level: 6, // Уровень сжатия (1-9, по умолчанию 6)
  threshold: 1024, // Минимальный размер для сжатия (1KB)
}));

app.use(express.json());
app.use('/api', apiLimiter); // Общий лимит для всех API запросов
// Явно указываем UTF-8 для всех JSON-ответов API (корректное отображение кириллицы).
app.use((req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = function (body) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return originalJson(body);
  };
  next();
});
app.use('/uploads', express.static(uploadsDir));

app.use('/auth', authRoutes);
app.use('/contacts', contactsRoutes);
app.use('/messages', messagesRoutes);
app.use('/chats', chatsRoutes);
app.use('/groups', groupsRoutes);
app.use('/users', usersRoutes);
app.use('/polls', pollsRoutes);

app.get('/health', (req, res) => res.json({ ok: true }));

// Веб-клиент (Flutter build) — отдаём по корню; без долгого кэша, чтобы после пуша сразу видеть изменения
app.use(express.static(publicDir, {
  setHeaders: (res, path) => {
    const p = path.toLowerCase();
    if (p.endsWith('.html') || p.endsWith('.js') || p.endsWith('.json'))
      res.setHeader('Cache-Control', 'no-cache, max-age=0, must-revalidate');
  },
}));
app.get(/^\/(?!auth|contacts|messages|users|polls|uploads|health|reset-password|ws)/, (req, res) => {
  const index = join(publicDir, 'index.html');
  if (existsSync(index)) {
    res.setHeader('Cache-Control', 'no-cache, max-age=0, must-revalidate');
    return res.sendFile(index);
  }
  res.status(404).send('Web client not deployed. Push to main to deploy, or run locally: flutter run -d chrome --dart-define=API_BASE_URL=http://THIS_SERVER:3000');
});

app.get('/reset-password', (req, res) => {
  const token = req.query.token || '';
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Сброс пароля</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 400px; margin: 2rem auto; padding: 1rem; }
    h1 { font-size: 1.25rem; }
    input { width: 100%; padding: 0.5rem; margin: 0.5rem 0; box-sizing: border-box; }
    button { padding: 0.6rem 1.2rem; margin-top: 0.5rem; cursor: pointer; }
    .error { color: #c00; font-size: 0.9rem; }
    .success { color: #080; font-size: 0.9rem; }
  </style>
</head>
<body>
  <h1>Новый пароль</h1>
  <form id="form" method="post" action="/auth/reset-password">
    <input type="hidden" name="token" value="${token.replace(/"/g, '&quot;')}">
    <label>Новый пароль (мин. 6 символов)</label>
    <input type="password" name="newPassword" required minlength="6" autocomplete="new-password">
    <label>Повторите пароль</label>
    <input type="password" id="confirm" required minlength="6" autocomplete="new-password">
    <div id="msg" class="error"></div>
    <button type="submit">Сохранить пароль</button>
  </form>
  <script>
    var form = document.getElementById('form');
    var confirm = document.getElementById('confirm');
    var msg = document.getElementById('msg');
    form.addEventListener('submit', function(e) {
      if (document.querySelector('input[name="newPassword"]').value !== confirm.value) {
        e.preventDefault();
        msg.textContent = 'Пароли не совпадают';
        return;
      }
      msg.textContent = '';
    });
    form.addEventListener('submit', function(e) {
      if (e.defaultPrevented) return;
      e.preventDefault();
      var fd = new FormData(form);
      fetch(form.action, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: fd.get('token'), newPassword: fd.get('newPassword') }) })
        .then(function(r) { return r.json().then(function(d) { return { ok: r.ok, d: d }; }); })
        .then(function(_) {
          if (_.ok) { msg.className = 'success'; msg.textContent = 'Пароль изменён. Можете войти в приложение.'; form.reset(); }
          else { msg.className = 'error'; msg.textContent = _.d.error || 'Ошибка'; }
        })
        .catch(function() { msg.className = 'error'; msg.textContent = 'Ошибка сети'; });
    });
  </script>
</body>
</html>
  `);
});

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url || '', `http://${req.headers.host}`);
  const token = url.searchParams.get('token');
  const payload = token ? verifyToken(token) : null;
  if (!payload) {
    ws.close(4001, 'Unauthorized');
    return;
  }
  const userId = payload.userId;
  if (!clients.has(userId)) clients.set(userId, new Set());
  clients.get(userId).add(ws);
  ws.userId = userId;

  ws.on('message', (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      if (data.type === 'call_signal' && data.toUserId != null && data.signal) {
        const toId = Number(data.toUserId);
        const set = clients.get(toId);
        const n = set ? set.size : 0;
        log.ws('call_signal', { fromUserId: userId, toUserId: toId, connections: n });
        broadcastToUser(toId, {
          type: 'call_signal',
          fromUserId: userId,
          signal: data.signal,
          payload: data.payload ?? null,
        });
      }
    } catch (_) {}
  });

  ws.on('close', () => {
    const set = clients.get(userId);
    if (set) {
      set.delete(ws);
      if (set.size === 0) clients.delete(userId);
    }
  });

  ws.on('error', (error) => {
    log.error('WebSocket error', error, { userId });
    ws.close();
  });
});

// Middleware для логирования HTTP запросов
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const responseTime = Date.now() - start;
    log.http(req, res, responseTime);
  });
  next();
});

const PORT = process.env.PORT || 3000;
if (process.env.NODE_ENV !== 'test') {
  server.listen(PORT, () => {
    log.info(`Server running at http://localhost:${PORT}`, { port: PORT, env: process.env.NODE_ENV });
  });
}

export { app, server };
