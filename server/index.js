import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import compression from 'compression';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { mkdirSync, existsSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { verifyToken } from './auth.js';
import { clients, broadcastToUser } from './realtime.js';
import db from './db.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { log } from './utils/logger.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import config from './config/index.js';

import authRoutes from './routes/auth.js';
import contactsRoutes from './routes/contacts.js';
import messagesRoutes from './routes/messages.js';
import usersRoutes from './routes/users.js';
import chatsRoutes from './routes/chats.js';
import groupsRoutes from './routes/groups.js';
import pollsRoutes from './routes/polls.js';
import searchRoutes from './routes/search.js';
import exportRoutes from './routes/export.js';
import pushRoutes from './routes/push.js';
import gdprRoutes from './routes/gdpr.js';
import mediaRoutes from './routes/media.js';
import syncRoutes from './routes/sync.js';
import swaggerUi from 'swagger-ui-express';
import { swaggerSpec } from './utils/swagger.js';
import { metricsMiddleware, getMetrics, metrics } from './utils/metrics.js';
import { initCache } from './utils/cache.js';
import { initFCM } from './utils/pushNotifications.js';
import { securityHeaders } from './middleware/security.js';
import { csrfProtect, csrfTokenRoute } from './middleware/csrf.js';
import { auditMiddleware } from './utils/auditLog.js';
import { getAllCircuitBreakerStates } from './utils/circuitBreaker.js';
import { apiVersioning, validateApiVersion } from './middleware/apiVersioning.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const uploadsDir = join(__dirname, 'uploads');
const publicDir = join(__dirname, 'public');
if (!existsSync(uploadsDir)) mkdirSync(uploadsDir, { recursive: true });
if (!existsSync(publicDir)) mkdirSync(publicDir, { recursive: true });

const app = express();
const server = createServer(app);

// Security headers (должен быть первым middleware)
app.use(securityHeaders());

// CORS настройка
app.use(cors({
  origin: (origin, callback) => {
    // Разрешаем запросы без origin (например, мобильные приложения, Postman)
    if (!origin) return callback(null, true);
    
    if (config.cors.origins.includes(origin) || config.nodeEnv === 'development') {
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
app.use(express.urlencoded({ extended: true })); // Для CSRF токенов в формах

// CSRF Protection (только для запросов без Bearer токена)
app.use(csrfProtect());

// Endpoint для получения CSRF токена (для веб-форм)
app.get('/csrf-token', csrfTokenRoute);

app.use('/api', apiLimiter); // Общий лимит для всех API запросов

// API Versioning (должен быть до routes, но после rate limiting)
app.use('/api', apiVersioning);
app.use('/api', validateApiVersion);
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

// Audit logging должен быть после auth middleware, но до routes
// (применяется автоматически через middleware в routes)

app.use('/auth', authRoutes);
app.use('/contacts', contactsRoutes);
app.use('/messages', messagesRoutes);
app.use('/chats', chatsRoutes);
app.use('/groups', groupsRoutes);
app.use('/users', usersRoutes);
app.use('/polls', pollsRoutes);
app.use('/search', searchRoutes);
app.use('/export', exportRoutes);
app.use('/push', pushRoutes);
app.use('/gdpr', gdprRoutes);
app.use('/media', mediaRoutes);
app.use('/sync', syncRoutes);

// Swagger UI для документации API
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
  customCss: '.swagger-ui .topbar { display: none }',
  customSiteTitle: 'Messenger API Documentation',
}));

// JSON схема для Swagger
app.get('/api-docs.json', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.send(swaggerSpec);
});

// Prometheus метрики endpoint
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    const metrics = await getMetrics();
    res.end(metrics);
  } catch (error) {
    log.error({ error }, 'Ошибка при получении метрик');
    res.status(500).end();
  }
});

// Health checks
app.get('/health', (req, res) => {
  const circuitBreakers = getAllCircuitBreakerStates();
  
  // Проверяем состояние circuit breakers
  const openCircuits = Object.entries(circuitBreakers)
    .filter(([_, state]) => state.state === 'OPEN')
    .map(([name, _]) => name);
  
  if (openCircuits.length > 0) {
    return res.status(503).json({
      status: 'degraded',
      message: 'Some services are unavailable',
      openCircuits,
      circuitBreakers,
    });
  }
  
  try {
    // Проверка базы данных
    const dbCheck = db.prepare('SELECT 1').get();
    if (!dbCheck) {
      return res.status(503).json({
        status: 'unhealthy',
        database: 'unavailable',
        circuitBreakers,
      });
    }

    // Проверка дискового пространства (упрощённая)
    const stats = statSync(process.env.MESSENGER_DB_PATH || join(__dirname, 'messenger.db'));
    const dbSize = stats.size;

    // Проверка памяти (упрощённая)
    const memUsage = process.memoryUsage();
    const memUsageMB = {
      rss: Math.round(memUsage.rss / 1024 / 1024),
      heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024),
      heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024),
      external: Math.round(memUsage.external / 1024 / 1024),
    };

    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: Math.round(process.uptime()),
      database: {
        status: 'connected',
        size: dbSize,
      },
      memory: memUsageMB,
      version: process.env.npm_package_version || '1.0.0',
    });
  } catch (error) {
    log.error('Health check failed', error);
    res.status(503).json({
      status: 'unhealthy',
      error: process.env.NODE_ENV === 'production' ? 'Service unavailable' : error.message,
    });
  }
});

// Readiness check (для Kubernetes/Docker)
app.get('/ready', (req, res) => {
  try {
    // Проверка базы данных
    const dbCheck = db.prepare('SELECT 1').get();
    if (!dbCheck) {
      return res.status(503).json({ ready: false, reason: 'database' });
    }
    res.json({ ready: true });
  } catch (error) {
    log.error('Readiness check failed', error);
    res.status(503).json({ ready: false, reason: 'database' });
  }
});

// Liveness check (для Kubernetes/Docker)
app.get('/live', (req, res) => {
  res.json({ alive: true });
});

// Обработка 404 ошибок (должен быть после всех маршрутов)
app.use(notFoundHandler);

// Централизованный обработчик ошибок (должен быть последним)
app.use(errorHandler);

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
  // Обновляем метрику подключений WebSocket
  metrics.websocket.connections.inc();
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
  
  // Обновляем статус пользователя на онлайн
  db.prepare('UPDATE users SET is_online = 1 WHERE id = ?').run(userId);
  // Уведомляем контакты об изменении статуса
  const contacts = db.prepare('SELECT contact_id FROM contacts WHERE user_id = ?').all(userId).map(r => r.contact_id);
  contacts.forEach(contactId => {
    broadcastToUser(contactId, {
      type: 'user_status',
      user_id: userId,
      is_online: true,
    });
  });

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
    // Обновляем метрику подключений WebSocket
    metrics.websocket.connections.dec();
    const set = clients.get(userId);
    if (set) {
      set.delete(ws);
      if (set.size === 0) {
        clients.delete(userId);
        // Обновляем статус пользователя на офлайн
        db.prepare('UPDATE users SET is_online = 0, last_seen = datetime(\'now\') WHERE id = ?').run(userId);
        // Уведомляем контакты об изменении статуса
        const contacts = db.prepare('SELECT contact_id FROM contacts WHERE user_id = ?').all(userId).map(r => r.contact_id);
        contacts.forEach(contactId => {
          broadcastToUser(contactId, {
            type: 'user_status',
            user_id: userId,
            is_online: false,
            last_seen: new Date().toISOString(),
          });
        });
      }
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

if (config.nodeEnv !== 'test') {
  // Инициализация кэша
  initCache();

  // Инициализация FCM для push-уведомлений
  initFCM().catch(err => {
    log.error({ error: err }, 'Ошибка инициализации FCM');
  });

  server.listen(config.port, () => {
    log.info(`Server running at http://localhost:${config.port}`, { port: config.port, env: config.nodeEnv });
  });
}

export { app, server };
