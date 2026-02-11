import csrf from 'csurf';

/**
 * CSRF Protection middleware
 * Защищает от межсайтовых подделок запросов
 * 
 * Примечание: CSRF токены требуются только для state-changing операций
 * (POST, PUT, PATCH, DELETE). GET запросы не требуют CSRF защиты.
 */
const csrfProtection = csrf({
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
  },
});

/**
 * Middleware для получения CSRF токена
 * Используется для GET запросов, которые возвращают формы
 */
export function getCsrfToken(req, res, next) {
  // Генерируем токен только если его еще нет
  if (!req.csrfToken) {
    return csrfProtection(req, res, () => {
      res.locals.csrfToken = req.csrfToken();
      next();
    });
  }
  res.locals.csrfToken = req.csrfToken();
  next();
}

/**
 * Middleware для защиты state-changing операций
 */
export function csrfProtect() {
  return (req, res, next) => {
    // Пропускаем GET, HEAD, OPTIONS запросы
    if (['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
      return next();
    }
    
    // Пропускаем WebSocket и API запросы с Bearer токеном
    // (они защищены JWT токенами)
    if (req.headers.authorization?.startsWith('Bearer ')) {
      return next();
    }
    
    // Применяем CSRF защиту для остальных запросов
    return csrfProtection(req, res, next);
  };
}

/**
 * Endpoint для получения CSRF токена (для веб-форм)
 */
export function csrfTokenRoute(req, res) {
  res.json({ csrfToken: req.csrfToken() });
}
