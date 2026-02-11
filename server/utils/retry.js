import { log } from './logger.js';

/**
 * Утилиты для повторных попыток выполнения операций
 * Защита от временных сбоев внешних сервисов
 */

const DEFAULT_RETRY_CONFIG = {
  maxAttempts: 3,
  initialDelay: 1000, // 1 секунда
  maxDelay: 10000, // 10 секунд
  backoffMultiplier: 2,
  retryableErrors: ['ECONNRESET', 'ETIMEDOUT', 'ENOTFOUND', 'ECONNREFUSED'],
};

/**
 * Задержка перед следующей попыткой
 */
function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Определить, является ли ошибка retryable
 */
function isRetryableError(error, retryableErrors) {
  if (!error) return false;
  
  // Проверяем код ошибки
  if (error.code && retryableErrors.includes(error.code)) {
    return true;
  }
  
  // Проверяем статус код HTTP (5xx ошибки)
  if (error.statusCode && error.statusCode >= 500 && error.statusCode < 600) {
    return true;
  }
  
  // Проверяем сообщение об ошибке
  if (error.message) {
    const message = error.message.toLowerCase();
    if (message.includes('timeout') || 
        message.includes('connection') ||
        message.includes('network')) {
      return true;
    }
  }
  
  return false;
}

/**
 * Выполнить операцию с повторными попытками
 */
export async function retry(fn, config = {}) {
  const {
    maxAttempts = DEFAULT_RETRY_CONFIG.maxAttempts,
    initialDelay = DEFAULT_RETRY_CONFIG.initialDelay,
    maxDelay = DEFAULT_RETRY_CONFIG.maxDelay,
    backoffMultiplier = DEFAULT_RETRY_CONFIG.backoffMultiplier,
    retryableErrors = DEFAULT_RETRY_CONFIG.retryableErrors,
    onRetry = null,
  } = { ...DEFAULT_RETRY_CONFIG, ...config };
  
  let lastError;
  let delayMs = initialDelay;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await fn();
      return result;
    } catch (error) {
      lastError = error;
      
      // Если это последняя попытка или ошибка не retryable, выбрасываем ошибку
      if (attempt === maxAttempts || !isRetryableError(error, retryableErrors)) {
        throw error;
      }
      
      // Логируем попытку повтора
      log.warn({
        attempt,
        maxAttempts,
        error: error.message,
        code: error.code,
        delay: delayMs,
      }, `Retry attempt ${attempt}/${maxAttempts}`);
      
      // Вызываем callback перед повтором
      if (onRetry) {
        onRetry(attempt, error, delayMs);
      }
      
      // Ждём перед следующей попыткой
      await delay(delayMs);
      
      // Увеличиваем задержку для следующей попытки (exponential backoff)
      delayMs = Math.min(delayMs * backoffMultiplier, maxDelay);
    }
  }
  
  throw lastError;
}

/**
 * Выполнить операцию с повторными попытками и возвратом результата или null
 */
export async function retryOrNull(fn, config = {}) {
  try {
    return await retry(fn, config);
  } catch (error) {
    log.error({ error }, 'Retry failed, returning null');
    return null;
  }
}

/**
 * Выполнить операцию с повторными попытками и значением по умолчанию
 */
export async function retryOrDefault(fn, defaultValue, config = {}) {
  try {
    return await retry(fn, config);
  } catch (error) {
    log.error({ error }, 'Retry failed, returning default value');
    return defaultValue;
  }
}
