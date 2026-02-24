import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { mkdirSync, existsSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { verifyToken } from './auth.js';
import { clients, broadcastToUser } from './realtime.js';
import db from './db.js';
import { apiLimiter } from './middleware/rateLimit.js';
import { log } from './utils/logger.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import config from './config/index.js';
import { handleHealth, handleReady, handleLive } from './health.js';
import { handleWsMessage } from './wsHandlers.js';

import authRoutes from './routes/auth.js';
import oauthRoutes from './routes/oauth.js';
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
import versionRoutes from './routes/version.js';
import swaggerUi from 'swagger-ui-express';
import { swaggerSpec } from './utils/swagger.js';
import metricsRegister, { getMetrics, metrics } from './utils/metrics.js';
import { initCache } from './utils/cache.js';
import { initFCM } from './utils/pushNotifications.js';
import { securityHeaders } from './middleware/security.js';
import { csrfProtect, getCsrfToken } from './middleware/csrf.js';
import { apiVersioning, validateApiVersion } from './middleware/apiVersioning.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const uploadsDir = join(__dirname, 'uploads');
const publicDir = join(__dirname, 'public');
if (!existsSync(uploadsDir)) mkdirSync(uploadsDir, { recursive: true });
if (!existsSync(publicDir)) mkdirSync(publicDir, { recursive: true });

const app = express();
// Trust proxy: только при явном TRUST_PROXY=true (за nginx и т.д.)
if (process.env.TRUST_PROXY === 'true') {
  app.set('trust proxy', 1);
} else {
  app.set('trust proxy', false);
}
const server = createServer(app);

// Security headers (должен быть первым middleware)
app.use(securityHeaders());

// Middleware для скурпулёзного логирования HTTP: START в начале, END при завершении
app.use((req, res, next) => {
  const start = Date.now();
  log.info(`[http] ${req.method} ${req.path} | START`, {
    file: 'http',
    action: `${req.method} ${req.path}`,
    phase: 'START',
    method: req.method,
    path: req.path,
    ip: req.ip || req.connection?.remoteAddress,
  });
  res.on('finish', () => {
    const responseTime = Date.now() - start;
    log.http(req, res, responseTime);
  });
  next();
});

// CORS настройка
app.use(cors({
  origin: (origin, callback) => {
    // Разрешаем запросы без origin (например, мобильные приложения, Postman)
    if (!origin) return callback(null, true);
    
    // В development разрешаем все origins
    if (config.nodeEnv === 'development') {
      return callback(null, true);
    }
    
    // В production разрешаем явно указанные origins или HTTPS домены (для Flutter web)
    if (config.cors.origins.includes(origin)) {
      return callback(null, true);
    }
    
    // Разрешаем HTTPS origins в production (для Flutter web приложений)
    if (config.nodeEnv === 'production' && origin.startsWith('https://')) {
      return callback(null, true);
    }
    
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  exposedHeaders: ['Content-Length'],
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

// express.json() не должен обрабатывать multipart/form-data - это делает multer
// Пропускаем multipart/form-data для express.json(), чтобы не мешать multer
app.use((req, res, next) => {
  const contentType = req.get('Content-Type') || '';
  if (contentType.startsWith('multipart/form-data')) {
    return next(); // Пропускаем multipart/form-data для multer
  }
  express.json()(req, res, next);
});
app.use(express.urlencoded({ extended: true })); // Для CSRF токенов в формах

// Cookie parser для CSRF защиты (требуется для работы csurf)
app.use(cookieParser());

// CSRF Protection применяется только к API маршрутам, исключая статические файлы и SPA маршруты
// Статические файлы и корневой путь не требуют CSRF защиты
// Auth endpoints (login, register) также исключены, так как используют JWT токены
app.use((req, res, next) => {
  const path = req.path;
  
  // Пропускаем статические файлы, корневой путь и другие не-API маршруты
  // ВАЖНО: проверяем путь ДО применения CSRF middleware
  if (
    path.startsWith('/uploads/') ||
    path.startsWith('/api-docs') ||
    path.startsWith('/health') ||
    path.startsWith('/metrics') ||
    path.startsWith('/live') ||
    path.startsWith('/ready') ||
    path.startsWith('/csrf-token') ||
    path === '/' ||
    // Исключаем auth endpoints (login, register) - они используют JWT токены
    path === '/auth/login' ||
    path === '/auth/register' ||
    path === '/auth/forgot-password' ||
    path === '/auth/reset-password' ||
    path.startsWith('/auth/oauth') ||
    // Пропускаем все пути, которые не начинаются с /api или /auth
    (!path.startsWith('/api') && !path.startsWith('/auth'))
  ) {
    return next();
  }
  
  // Применяем CSRF защиту только к API маршрутам и некоторым auth маршрутам (например, смена пароля для авторизованных)
  return csrfProtect()(req, res, next);
});

// Endpoint для получения CSRF токена (для веб-форм)
// Используем getCsrfToken middleware для генерации токена
app.get('/csrf-token', getCsrfToken, (req, res) => {
  res.json({ csrfToken: res.locals.csrfToken });
});

app.use('/api', apiLimiter); // Общий лимит для всех API запросов

// API Versioning (должен быть до routes, но после rate limiting)
// Применяем ко всем путям, не только к /api
app.use(apiVersioning);
app.use(validateApiVersion);
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

// API маршруты (должны быть ДО статических файлов, чтобы не перехватывались)
app.use('/auth', authRoutes);
app.use('/auth/oauth', oauthRoutes);
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
    res.set('Content-Type', metricsRegister.contentType);
    const body = await getMetrics();
    res.end(body);
  } catch (error) {
    log.error({ error }, 'Ошибка при получении метрик');
    res.status(500).end();
  }
});

// Version endpoint (до health checks, чтобы не требовал аутентификации)
app.use('/version', versionRoutes);

// Health checks (логика в server/health.js)
app.get('/health', (req, res) => handleHealth(db, req, res));
app.get('/ready', (req, res) => handleReady(db, req, res));
app.get('/live', (req, res) => handleLive(req, res));

// Веб-клиент (Flutter build) — отдаём статические файлы и fallback для SPA роутинга
// Без долгого кэша, чтобы после пуша сразу видеть изменения
// ВАЖНО: express.static обрабатывает только GET запросы, поэтому API маршруты (POST/PUT/DELETE) не будут перехвачены
app.use(express.static(publicDir, {
  setHeaders: (res, path) => {
    const p = path.toLowerCase();
    if (p.endsWith('.html') || p.endsWith('.js') || p.endsWith('.json'))
      res.setHeader('Cache-Control', 'no-cache, max-age=0, must-revalidate');
  },
}));

// Шаблон страницы сброса пароля (читается при старте)
const resetPasswordTemplatePath = join(__dirname, 'templates', 'reset-password.html');
const resetPasswordTemplate = existsSync(resetPasswordTemplatePath)
  ? readFileSync(resetPasswordTemplatePath, 'utf8')
  : null;

// Обработчик для сброса пароля (должен быть до SPA fallback)
app.get('/reset-password', (req, res) => {
  const token = (req.query.token || '').replace(/"/g, '&quot;');
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (resetPasswordTemplate) {
    res.send(resetPasswordTemplate.replace('{{TOKEN}}', token));
  } else {
    res.status(500).send('Reset password template not found.');
  }
});

// Fallback для SPA роутинга - отдаём index.html для всех путей, кроме API
app.get(/^\/(?!auth|contacts|messages|users|polls|uploads|health|reset-password|ws|api|api-docs|metrics|csrf-token|live|ready)/, (req, res) => {
  const index = join(publicDir, 'index.html');
  if (existsSync(index)) {
    res.setHeader('Cache-Control', 'no-cache, max-age=0, must-revalidate');
    return res.sendFile(index);
  }
  res.status(404).send('Web client not deployed. Push to main to deploy, or run locally: flutter run -d chrome --dart-define=API_BASE_URL=http://THIS_SERVER:3000');
});

// Обработка 404 ошибок (должен быть после всех маршрутов)
app.use(notFoundHandler);

// Централизованный обработчик ошибок (должен быть последним)
// Обработка необработанных исключений и промисов
process.on('uncaughtException', (err) => {
  log.error({ error: err, stack: err.stack }, 'Uncaught Exception - Server will exit');
  // Даем время на логирование перед выходом
  setTimeout(() => {
    process.exit(1);
  }, 1000);
});

process.on('unhandledRejection', (reason, promise) => {
  log.error({ reason, promise }, 'Unhandled Rejection');
});

app.use(errorHandler);

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
  const userClients = clients.get(userId);
  if (userClients) {
    userClients.add(ws);
  }
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
    handleWsMessage(raw, { userId, req, db }).catch(() => {});
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
