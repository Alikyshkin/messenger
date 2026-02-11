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
  
  // HTTP запросы
  http: (req, res, responseTime) => {
    logger.info({
      method: req.method,
      url: sanitizeUrl(req.url),
      statusCode: res.statusCode,
      responseTime: `${responseTime}ms`,
      ip: req.ip || req.connection?.remoteAddress,
      userAgent: req.get('user-agent'),
      // Не логируем заголовки с чувствительными данными
    }, 'HTTP request');
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
