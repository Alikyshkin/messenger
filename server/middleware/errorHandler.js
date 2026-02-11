import { log } from '../utils/logger.js';
import { sanitizeRequest } from '../utils/sanitizeLogs.js';

/**
 * Централизованный обработчик ошибок
 */
export function errorHandler(err, req, res, next) {
  // Логируем ошибку с санитизированными данными
  const sanitizedReq = sanitizeRequest(req);
  log.error('Request error', err, {
    ...sanitizedReq,
    userId: req.user?.userId,
  });

  // Ошибки валидации (Joi)
  if (err.isJoi) {
    return res.status(400).json({
      error: 'Ошибка валидации',
      details: err.details?.map(d => d.message) || [err.message],
    });
  }

  // Ошибки базы данных
  if (err.code && err.code.startsWith('SQLITE_')) {
    // Не раскрываем детали SQL ошибок в продакшене
    if (process.env.NODE_ENV === 'production') {
      return res.status(500).json({
        error: 'Ошибка базы данных',
      });
    }
    return res.status(500).json({
      error: 'Ошибка базы данных',
      details: err.message,
    });
  }

  // Ошибки аутентификации
  if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
    return res.status(401).json({
      error: 'Недействительный токен',
    });
  }

  // Ошибки CORS
  if (err.message === 'Not allowed by CORS') {
    return res.status(403).json({
      error: 'Доступ запрещён',
    });
  }

  // Ошибки rate limiting
  if (err.status === 429) {
    return res.status(429).json({
      error: err.message || 'Слишком много запросов',
    });
  }

  // Ошибки файлов
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(400).json({
      error: 'Файл слишком большой',
    });
  }

  // Ошибки multer
  if (err.name === 'MulterError') {
    return res.status(400).json({
      error: err.message || 'Ошибка загрузки файла',
    });
  }

  // Статус код из ошибки
  const statusCode = err.statusCode || err.status || 500;

  // В продакшене не раскрываем детали ошибок
  if (process.env.NODE_ENV === 'production' && statusCode === 500) {
    return res.status(500).json({
      error: 'Внутренняя ошибка сервера',
    });
  }

  // В development показываем полную информацию
  return res.status(statusCode).json({
    error: err.message || 'Внутренняя ошибка сервера',
    ...(process.env.NODE_ENV !== 'production' && {
      stack: err.stack,
      details: err,
    }),
  });
}

/**
 * Middleware для обработки 404 ошибок
 */
export function notFoundHandler(req, res, next) {
  res.status(404).json({
    error: 'Маршрут не найден',
    path: req.url,
  });
}

/**
 * Обёртка для асинхронных обработчиков маршрутов
 * Автоматически ловит ошибки и передаёт их в errorHandler
 */
export function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
