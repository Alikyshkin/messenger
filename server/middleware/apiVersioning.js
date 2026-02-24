/**
 * API Versioning Middleware
 * Поддержка версионирования API для обратной совместимости.
 * Маршруты не используют префикс /api/v1; версия задаётся заголовком Accept или query-параметром.
 */

const DEFAULT_VERSION = 'v1';

/**
 * Middleware для извлечения версии API из заголовка Accept или query-параметра
 */
export function apiVersioning(req, res, next) {
  const acceptHeader = req.get('Accept') || '';
  const versionMatch = acceptHeader.match(/version=(\d+)/);
  const queryVersion = req.query.api_version;

  let version = DEFAULT_VERSION;
  if (versionMatch) {
    version = `v${versionMatch[1]}`;
  } else if (queryVersion) {
    version = `v${queryVersion}`;
  }

  req.apiVersion = version;
  res.setHeader('X-API-Version', version);
  next();
}

/**
 * Проверить, поддерживается ли версия API
 */
export function isVersionSupported(version) {
  const supportedVersions = ['v1'];
  return supportedVersions.includes(version);
}

/**
 * Middleware для проверки поддерживаемых версий
 */
export function validateApiVersion(req, res, next) {
  // Если apiVersion не установлен (для путей без /api), используем версию по умолчанию
  const version = req.apiVersion || DEFAULT_VERSION;
  
  if (!isVersionSupported(version)) {
    return res.status(400).json({
      error: `Версия API ${version} не поддерживается`,
      supportedVersions: ['v1'],
      code: 'UNSUPPORTED_API_VERSION',
    });
  }
  
  // Устанавливаем версию, если она еще не установлена
  if (!req.apiVersion) {
    req.apiVersion = version;
  }
  
  next();
}
