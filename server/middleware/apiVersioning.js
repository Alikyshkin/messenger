/**
 * API Versioning Middleware
 * Поддержка версионирования API для обратной совместимости
 */

const API_VERSION = 'v1';
const DEFAULT_VERSION = 'v1';

/**
 * Middleware для извлечения версии API из заголовка или URL
 */
export function apiVersioning(req, res, next) {
  // Проверяем заголовок Accept: application/vnd.api+json;version=1
  const acceptHeader = req.get('Accept') || '';
  const versionMatch = acceptHeader.match(/version=(\d+)/);
  
  // Или из URL: /api/v1/users
  const urlMatch = req.path.match(/^\/api\/v(\d+)\//);
  
  // Или из query параметра: ?api_version=1
  const queryVersion = req.query.api_version;
  
  let version = DEFAULT_VERSION;
  
  if (versionMatch) {
    version = `v${versionMatch[1]}`;
  } else if (urlMatch) {
    version = `v${urlMatch[1]}`;
    // Удаляем версию из пути для дальнейшей обработки
    req.url = req.url.replace(`/api/${version}`, '/api');
    req.path = req.path.replace(`/api/${version}`, '/api');
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
  if (!isVersionSupported(req.apiVersion)) {
    return res.status(400).json({
      error: `Версия API ${req.apiVersion} не поддерживается`,
      supportedVersions: ['v1'],
      code: 'UNSUPPORTED_API_VERSION',
    });
  }
  next();
}
