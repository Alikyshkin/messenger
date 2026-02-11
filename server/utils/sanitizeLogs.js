/**
 * Утилиты для удаления чувствительных данных из логов
 */

const SENSITIVE_FIELDS = [
  'password',
  'password_hash',
  'passwordHash',
  'token',
  'authorization',
  'auth',
  'secret',
  'api_key',
  'apiKey',
  'apikey',
  'access_token',
  'accessToken',
  'refresh_token',
  'refreshToken',
  'credit_card',
  'creditCard',
  'card_number',
  'cardNumber',
  'cvv',
  'ssn',
  'email', // Опционально, можно замаскировать
];

const MASK = '***REDACTED***';

/**
 * Рекурсивно удаляет чувствительные поля из объекта
 */
export function sanitizeObject(obj, depth = 0, maxDepth = 10) {
  if (depth > maxDepth) {
    return '[Max depth reached]';
  }
  
  if (obj === null || obj === undefined) {
    return obj;
  }
  
  if (typeof obj !== 'object') {
    return obj;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(item => sanitizeObject(item, depth + 1, maxDepth));
  }
  
  const sanitized = {};
  
  for (const [key, value] of Object.entries(obj)) {
    const lowerKey = key.toLowerCase();
    
    // Проверяем, является ли поле чувствительным
    const isSensitive = SENSITIVE_FIELDS.some(field => 
      lowerKey.includes(field.toLowerCase())
    );
    
    if (isSensitive) {
      sanitized[key] = MASK;
    } else if (typeof value === 'object' && value !== null) {
      sanitized[key] = sanitizeObject(value, depth + 1, maxDepth);
    } else {
      sanitized[key] = value;
    }
  }
  
  return sanitized;
}

/**
 * Удаляет чувствительные данные из строки запроса
 */
export function sanitizeUrl(url) {
  if (!url || typeof url !== 'string') {
    return url;
  }
  
  try {
    const urlObj = new URL(url, 'http://localhost');
    const sensitiveParams = ['token', 'password', 'secret', 'api_key', 'key'];
    
    sensitiveParams.forEach(param => {
      if (urlObj.searchParams.has(param)) {
        urlObj.searchParams.set(param, MASK);
      }
    });
    
    return urlObj.pathname + urlObj.search;
  } catch {
    // Если URL невалидный, возвращаем как есть
    return url;
  }
}

/**
 * Удаляет чувствительные данные из заголовков
 */
export function sanitizeHeaders(headers) {
  if (!headers || typeof headers !== 'object') {
    return headers;
  }
  
  const sanitized = { ...headers };
  const sensitiveHeaders = [
    'authorization',
    'cookie',
    'x-api-key',
    'x-auth-token',
  ];
  
  sensitiveHeaders.forEach(header => {
    const lowerHeader = header.toLowerCase();
    for (const key in sanitized) {
      if (key.toLowerCase() === lowerHeader) {
        sanitized[key] = MASK;
      }
    }
  });
  
  return sanitized;
}

/**
 * Удаляет чувствительные данные из тела запроса
 */
export function sanitizeBody(body) {
  if (!body) {
    return body;
  }
  
  if (typeof body === 'string') {
    try {
      const parsed = JSON.parse(body);
      return JSON.stringify(sanitizeObject(parsed));
    } catch {
      // Если не JSON, проверяем на наличие чувствительных данных
      if (body.toLowerCase().includes('password') || body.toLowerCase().includes('token')) {
        return MASK;
      }
      return body;
    }
  }
  
  return sanitizeObject(body);
}

/**
 * Полная санитизация данных запроса для логирования
 */
export function sanitizeRequest(req) {
  return {
    method: req.method,
    url: sanitizeUrl(req.url),
    headers: sanitizeHeaders(req.headers),
    body: sanitizeBody(req.body),
    query: sanitizeObject(req.query),
    params: sanitizeObject(req.params),
    ip: req.ip || req.connection?.remoteAddress,
    userAgent: req.get('user-agent'),
  };
}
