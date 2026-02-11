import client from 'prom-client';

// Создаём Registry для метрик
const register = new client.Registry();

// Добавляем стандартные метрики Node.js
client.collectDefaultMetrics({ register });

// HTTP метрики
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.5, 1, 2, 5, 10],
  registers: [register],
});

const httpRequestTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestSize = new client.Histogram({
  name: 'http_request_size_bytes',
  help: 'Size of HTTP requests in bytes',
  labelNames: ['method', 'route'],
  buckets: [100, 1000, 10000, 100000, 1000000],
  registers: [register],
});

const httpResponseSize = new client.Histogram({
  name: 'http_response_size_bytes',
  help: 'Size of HTTP responses in bytes',
  labelNames: ['method', 'route'],
  buckets: [100, 1000, 10000, 100000, 1000000],
  registers: [register],
});

// WebSocket метрики
const wsConnections = new client.Gauge({
  name: 'websocket_connections_total',
  help: 'Total number of WebSocket connections',
  registers: [register],
});

const wsMessagesTotal = new client.Counter({
  name: 'websocket_messages_total',
  help: 'Total number of WebSocket messages',
  labelNames: ['type'],
  registers: [register],
});

// Database метрики
const dbQueryDuration = new client.Histogram({
  name: 'database_query_duration_seconds',
  help: 'Duration of database queries in seconds',
  labelNames: ['operation'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1],
  registers: [register],
});

const dbQueryTotal = new client.Counter({
  name: 'database_queries_total',
  help: 'Total number of database queries',
  labelNames: ['operation', 'status'],
  registers: [register],
});

// Бизнес метрики
const messagesTotal = new client.Counter({
  name: 'messages_total',
  help: 'Total number of messages sent',
  labelNames: ['type'], // 'personal' or 'group'
  registers: [register],
});

const usersTotal = new client.Gauge({
  name: 'users_total',
  help: 'Total number of registered users',
  registers: [register],
});

const activeUsers = new client.Gauge({
  name: 'active_users',
  help: 'Number of active users (online)',
  registers: [register],
});

// Middleware для отслеживания HTTP запросов
export function metricsMiddleware(req, res, next) {
  const start = Date.now();
  const route = req.route?.path || req.path || 'unknown';
  
  // Отслеживаем размер запроса
  if (req.headers['content-length']) {
    httpRequestSize.observe(
      { method: req.method, route },
      parseInt(req.headers['content-length'], 10)
    );
  }
  
  // Отслеживаем размер ответа
  const originalSend = res.send;
  res.send = function (body) {
    if (body) {
      const size = Buffer.byteLength(body, 'utf8');
      httpResponseSize.observe({ method: req.method, route }, size);
    }
    return originalSend.call(this, body);
  };
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const statusCode = res.statusCode.toString();
    
    httpRequestDuration.observe(
      { method: req.method, route, status_code: statusCode },
      duration
    );
    
    httpRequestTotal.inc({
      method: req.method,
      route,
      status_code: statusCode,
    });
  });
  
  next();
}

// Функция для получения метрик в формате Prometheus
export async function getMetrics() {
  return register.metrics();
}

// Экспортируем метрики для использования в других модулях
export const metrics = {
  http: {
    requestDuration: httpRequestDuration,
    requestTotal: httpRequestTotal,
    requestSize: httpRequestSize,
    responseSize: httpResponseSize,
  },
  websocket: {
    connections: wsConnections,
    messagesTotal: wsMessagesTotal,
  },
  database: {
    queryDuration: dbQueryDuration,
    queryTotal: dbQueryTotal,
  },
  business: {
    messagesTotal,
    usersTotal,
    activeUsers,
  },
};

export default register;
