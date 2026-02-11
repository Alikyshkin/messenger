import Redis from 'ioredis';
import { log } from './logger.js';
import config from '../config/index.js';
import { retryOrNull } from './retry.js';

let redis = null;
let cacheEnabled = false;

/**
 * Инициализация Redis подключения
 */
export function initCache() {
  const redisUrl = process.env.REDIS_URL || config.redis?.url;
  
  if (!redisUrl) {
    log.warn('Redis URL не указан, кэширование отключено');
    return;
  }
  
  try {
    redis = new Redis(redisUrl, {
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: true,
    });
    
    redis.on('connect', () => {
      log.info('Redis подключен');
      cacheEnabled = true;
    });
    
    redis.on('error', (error) => {
      log.error({ error }, 'Ошибка Redis');
      cacheEnabled = false;
    });
    
    redis.on('close', () => {
      log.warn('Redis соединение закрыто');
      cacheEnabled = false;
    });
    
    redis.connect().catch((error) => {
      log.error({ error }, 'Не удалось подключиться к Redis');
      cacheEnabled = false;
    });
  } catch (error) {
    log.error({ error }, 'Ошибка инициализации Redis');
    cacheEnabled = false;
  }
}

/**
 * Получить значение из кэша
 */
export async function get(key) {
  if (!cacheEnabled || !redis) {
    return null;
  }
  
  try {
    const value = await retryOrNull(
      () => redis.get(key),
      {
        maxAttempts: 2,
        initialDelay: 100,
      }
    );
    
    if (value === null) {
      return null;
    }
    return JSON.parse(value);
  } catch (error) {
    log.error({ error, key }, 'Ошибка получения из кэша');
    return null;
  }
}

/**
 * Сохранить значение в кэш
 */
export async function set(key, value, ttlSeconds = null) {
  if (!cacheEnabled || !redis) {
    return false;
  }
  
  try {
    const serialized = JSON.stringify(value);
    if (ttlSeconds) {
      await redis.setex(key, ttlSeconds, serialized);
    } else {
      await redis.set(key, serialized);
    }
    return true;
  } catch (error) {
    log.error({ error, key }, 'Ошибка сохранения в кэш');
    return false;
  }
}

/**
 * Удалить значение из кэша
 */
export async function del(key) {
  if (!cacheEnabled || !redis) {
    return false;
  }
  
  try {
    await redis.del(key);
    return true;
  } catch (error) {
    log.error({ error, key }, 'Ошибка удаления из кэша');
    return false;
  }
}

/**
 * Удалить все ключи по паттерну
 */
export async function delPattern(pattern) {
  if (!cacheEnabled || !redis) {
    return false;
  }
  
  try {
    const stream = redis.scanStream({
      match: pattern,
      count: 100,
    });
    
    const keys = [];
    stream.on('data', (resultKeys) => {
      keys.push(...resultKeys);
    });
    
    return new Promise((resolve, reject) => {
      stream.on('end', async () => {
        if (keys.length > 0) {
          await redis.del(...keys);
        }
        resolve(true);
      });
      stream.on('error', reject);
    });
  } catch (error) {
    log.error({ error, pattern }, 'Ошибка удаления по паттерну');
    return false;
  }
}

/**
 * Проверить существование ключа
 */
export async function exists(key) {
  if (!cacheEnabled || !redis) {
    return false;
  }
  
  try {
    const result = await redis.exists(key);
    return result === 1;
  } catch (error) {
    log.error({ error, key }, 'Ошибка проверки существования ключа');
    return false;
  }
}

/**
 * Установить TTL для ключа
 */
export async function expire(key, seconds) {
  if (!cacheEnabled || !redis) {
    return false;
  }
  
  try {
    await redis.expire(key, seconds);
    return true;
  } catch (error) {
    log.error({ error, key }, 'Ошибка установки TTL');
    return false;
  }
}

/**
 * Получить несколько значений
 */
export async function mget(...keys) {
  if (!cacheEnabled || !redis || keys.length === 0) {
    return [];
  }
  
  try {
    const values = await redis.mget(...keys);
    return values.map((v) => (v === null ? null : JSON.parse(v)));
  } catch (error) {
    log.error({ error, keys }, 'Ошибка получения нескольких значений');
    return [];
  }
}

/**
 * Сохранить несколько значений
 */
export async function mset(keyValuePairs, ttlSeconds = null) {
  if (!cacheEnabled || !redis || keyValuePairs.length === 0) {
    return false;
  }
  
  try {
    const pipeline = redis.pipeline();
    for (let i = 0; i < keyValuePairs.length; i += 2) {
      const key = keyValuePairs[i];
      const value = JSON.stringify(keyValuePairs[i + 1]);
      if (ttlSeconds) {
        pipeline.setex(key, ttlSeconds, value);
      } else {
        pipeline.set(key, value);
      }
    }
    await pipeline.exec();
    return true;
  } catch (error) {
    log.error({ error }, 'Ошибка сохранения нескольких значений');
    return false;
  }
}

/**
 * Инкремент значения
 */
export async function incr(key) {
  if (!cacheEnabled || !redis) {
    return null;
  }
  
  try {
    return await redis.incr(key);
  } catch (error) {
    log.error({ error, key }, 'Ошибка инкремента');
    return null;
  }
}

/**
 * Декремент значения
 */
export async function decr(key) {
  if (!cacheEnabled || !redis) {
    return null;
  }
  
  try {
    return await redis.decr(key);
  } catch (error) {
    log.error({ error, key }, 'Ошибка декремента');
    return null;
  }
}

/**
 * Закрыть соединение с Redis
 */
export async function close() {
  if (redis) {
    await redis.quit();
    redis = null;
    cacheEnabled = false;
  }
}

/**
 * Проверить, включено ли кэширование
 */
export function isEnabled() {
  return cacheEnabled;
}

// Ключи для кэширования
export const CacheKeys = {
  user: (userId) => `user:${userId}`,
  userContacts: (userId) => `user:${userId}:contacts`,
  userChats: (userId) => `user:${userId}:chats`,
  message: (messageId) => `message:${messageId}`,
  group: (groupId) => `group:${groupId}`,
  groupMembers: (groupId) => `group:${groupId}:members`,
  session: (token) => `session:${token}`,
  onlineUsers: () => 'online:users',
};
