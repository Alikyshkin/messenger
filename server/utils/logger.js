import pino from 'pino';
import { sanitizeUrl, sanitizeHeaders } from './sanitizeLogs.js';

const isDevelopment = process.env.NODE_ENV === 'development' || process.env.NODE_ENV !== 'production';

// Создаём логгер с настройками для разных окружений
const logger = pino({
  level: process.env.LOG_LEVEL || (isDevelopment ? 'debug' : 'info'),
  transport: isDevelopment
    ? {
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'HH:MM:ss Z',
          ignore: 'pid,hostname',
        },
      }
    : undefined,
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

// Вспомогательные методы для структурированного логирования
export const log = {
  // Общая информация
  info: (message, data = {}) => {
    logger.info(data, message);
  },
  
  // Отладочная информация
  debug: (message, data = {}) => {
    logger.debug(data, message);
  },
  
  // Предупреждения
  warn: (message, data = {}) => {
    logger.warn(data, message);
  },
  
  // Ошибки
  error: (message, error = null, data = {}) => {
    const errorData = {
      ...data,
      ...(error && {
        error: {
          message: error.message,
          stack: error.stack,
          name: error.name,
          ...(error.code && { code: error.code }),
        },
      }),
    };
    logger.error(errorData, message);
  },
  
  // HTTP запросы — скурпулёзно: метод, путь, статус, время, userId
  http: (req, res, responseTime) => {
    const data = {
      file: 'http',
      action: `${req.method} ${req.path}`,
      phase: 'END',
      method: req.method,
      path: req.path,
      url: sanitizeUrl(req.url),
      statusCode: res.statusCode,
      responseTime: `${responseTime}ms`,
      ip: req.ip || req.connection?.remoteAddress,
      userAgent: req.get('user-agent'),
    };
    if (req.user?.userId) data.userId = req.user.userId;
    logger.info(data, `[http] ${req.method} ${req.path} ${res.statusCode} ${responseTime}ms`);
  },

  // Лог маршрута: файл, действие, фаза (START/END/ERROR), детали
  route: (file, action, phase, details = {}, reason = null) => {
    const data = { file, action, phase, ...details };
    if (reason) data.reason = reason;
    const msg = `[${file}] ${action} | ${phase}${Object.keys(details).length ? ' | ' + JSON.stringify(details) : ''}${reason ? ' | ' + reason : ''}`;
    if (phase === 'ERROR') logger.error(data, msg);
    else logger.info(data, msg);
  },
  
  // WebSocket события
  ws: (event, data = {}) => {
    logger.debug(data, `WebSocket: ${event}`);
  },
  
  // База данных операции
  db: (operation, data = {}) => {
    logger.debug(data, `DB: ${operation}`);
  },
};

export default logger;
