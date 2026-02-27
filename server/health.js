import { statSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { getAllCircuitBreakerStates } from './utils/circuitBreaker.js';
import { log } from './utils/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Проверка доступности БД для health/ready эндпоинтов.
 * @param {import('better-sqlite3').Database} db
 * @returns {{ ok: true } | { ok: false; error?: Error }}
 */
export function checkDatabase(db) {
  try {
    const result = db.prepare('SELECT 1').get();
    if (!result) {
      return { ok: false };
    }
    return { ok: true };
  } catch (error) {
    return { ok: false, error };
  }
}

/**
 * Обработчик GET /health: проверка БД, circuit breakers, памяти.
 * @param {import('better-sqlite3').Database} db
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 */
export function handleHealth(db, req, res) {
  const circuitBreakers = getAllCircuitBreakerStates();
  const openCircuits = Object.entries(circuitBreakers)
    .filter(([, state]) => state.state === 'OPEN')
    .map(([name]) => name);

  if (openCircuits.length > 0) {
    return res.status(503).json({
      status: 'degraded',
      message: 'Some services are unavailable',
      openCircuits,
      circuitBreakers,
    });
  }

  try {
    const dbResult = checkDatabase(db);
    if (!dbResult.ok) {
      if (dbResult.error) log.error('Health check DB error', dbResult.error);
      return res.status(503).json({
        status: 'unhealthy',
        database: 'unavailable',
        circuitBreakers,
      });
    }

    const currentDbPath = process.env.MESSENGER_DB_PATH || join(__dirname, 'messenger.db');
    let dbSize = 0;
    if (currentDbPath !== ':memory:') {
      try {
        const stats = statSync(currentDbPath);
        dbSize = stats.size;
      } catch (_) { /* файл ещё не создан */ }
    }
    const memUsage = process.memoryUsage();
    const memUsageMB = {
      rss: Math.round(memUsage.rss / 1024 / 1024),
      heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024),
      heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024),
      external: Math.round(memUsage.external / 1024 / 1024),
    };

    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: Math.round(process.uptime()),
      database: { status: 'connected', size: dbSize },
      memory: memUsageMB,
      version: process.env.npm_package_version || '1.0.0',
    });
  } catch (error) {
    log.error('Health check failed', error);
    res.status(503).json({
      status: 'unhealthy',
      error: process.env.NODE_ENV === 'production' ? 'Сервис недоступен' : error.message,
    });
  }
}

/**
 * Обработчик GET /ready (readiness check).
 * @param {import('better-sqlite3').Database} db
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 */
export function handleReady(db, req, res) {
  const dbResult = checkDatabase(db);
  if (!dbResult.ok) {
    if (dbResult.error) log.error('Readiness check failed', dbResult.error);
    return res.status(503).json({ ready: false, reason: 'database' });
  }
  res.json({ ready: true });
}

/**
 * Обработчик GET /live (liveness check).
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 */
export function handleLive(req, res) {
  res.json({ alive: true });
}
