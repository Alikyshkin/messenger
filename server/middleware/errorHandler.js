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
    const errors = err.details?.map(d => {
      // Улучшаем сообщения об ошибках
      let message = d.message;
      
      // Переводим технические сообщения в понятные
      message = message.replace(/\"([^\"]+)\"/g, '$1'); // Убираем кавычки
      message = message.replace(/must be/, 'должно быть');
      message = message.replace(/is required/, 'обязательно для заполнения');
      message = message.replace(/must be one of/, 'должно быть одним из');
      message = message.replace(/length must be/, 'длина должна быть');
      message = message.replace(/at least/, 'минимум');
      message = message.replace(/at most/, 'максимум');
      message = message.replace(/characters long/, 'символов');
      
      return message;
    }) || [err.message];
    
    return res.status(400).json({
      error: 'Ошибка валидации данных',
      details: errors,
      message: errors.length === 1 ? errors[0] : 'Проверьте правильность введённых данных',
    });
  }

  // Ошибки базы данных
  if (err.code && err.code.startsWith('SQLITE_')) {
    // Не раскрываем детали SQL ошибок в продакшене
    if (process.env.NODE_ENV === 'production') {
      return res.status(500).json({
        error: 'Произошла ошибка при работе с данными. Пожалуйста, попробуйте позже.',
        code: 'DATABASE_ERROR',
      });
    }
    
    // В development показываем больше информации
    let userMessage = 'Ошибка базы данных';
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      userMessage = 'Запись с такими данными уже существует';
    } else if (err.code === 'SQLITE_CONSTRAINT_FOREIGNKEY') {
      userMessage = 'Невозможно выполнить операцию: связанные данные не найдены';
    } else if (err.code === 'SQLITE_BUSY') {
      userMessage = 'База данных занята. Пожалуйста, попробуйте через несколько секунд';
    }
    
    return res.status(500).json({
      error: userMessage,
      code: err.code,
      ...(process.env.NODE_ENV !== 'production' && { details: err.message }),
    });
  }

  // Ошибки аутентификации
  if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
    let message = 'Сессия истекла или токен недействителен';
    if (err.name === 'TokenExpiredError') {
      message = 'Ваша сессия истекла. Пожалуйста, войдите заново';
    } else if (err.name === 'JsonWebTokenError') {
      message = 'Ошибка аутентификации. Пожалуйста, войдите заново';
    }
    
    return res.status(401).json({
      error: message,
      code: 'AUTH_ERROR',
      requiresLogin: true,
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
      error: err.message || 'Слишком много запросов. Пожалуйста, подождите немного перед следующей попыткой',
      code: 'RATE_LIMIT_EXCEEDED',
      retryAfter: err.retryAfter || 60, // секунды
    });
  }

  // Ошибки файлов
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(400).json({
      error: 'Размер файла превышает допустимый лимит. Пожалуйста, выберите файл меньшего размера',
      code: 'FILE_TOO_LARGE',
      maxSize: err.limit || 'неизвестно',
    });
  }
  
  if (err.code === 'LIMIT_FILE_COUNT') {
    return res.status(400).json({
      error: 'Превышено максимальное количество файлов. Пожалуйста, отправьте меньше файлов за раз',
      code: 'TOO_MANY_FILES',
    });
  }
  
  if (err.code === 'LIMIT_UNEXPECTED_FILE') {
    return res.status(400).json({
      error: 'Неожиданное поле файла. Проверьте имя поля при загрузке',
      code: 'INVALID_FILE_FIELD',
    });
  }

  // Ошибки multer
  if (err.name === 'MulterError') {
    let message = 'Ошибка при загрузке файла';
    
    if (err.code === 'LIMIT_FILE_SIZE') {
      message = 'Файл слишком большой. Максимальный размер: ' + (err.limit / 1024 / 1024).toFixed(2) + ' МБ';
    } else if (err.code === 'LIMIT_FILE_COUNT') {
      message = 'Превышено максимальное количество файлов';
    } else if (err.code === 'LIMIT_UNEXPECTED_FILE') {
      message = 'Неожиданное поле файла';
    } else {
      message = err.message || 'Ошибка при загрузке файла. Проверьте формат и размер файла';
    }
    
    return res.status(400).json({
      error: message,
      code: 'UPLOAD_ERROR',
    });
  }

  // Статус код из ошибки
  const statusCode = err.statusCode || err.status || 500;

  // В продакшене не раскрываем детали ошибок
  if (process.env.NODE_ENV === 'production' && statusCode === 500) {
    return res.status(500).json({
      error: 'Произошла внутренняя ошибка сервера. Мы уже работаем над её устранением. Пожалуйста, попробуйте позже',
      code: 'INTERNAL_ERROR',
      requestId: req.id || Date.now().toString(36), // Для отслеживания в логах
    });
  }

  // В development показываем полную информацию
  return res.status(statusCode).json({
    error: err.message || 'Внутренняя ошибка сервера',
    code: err.code || 'UNKNOWN_ERROR',
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
