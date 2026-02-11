import { log } from './logger.js';

/**
 * Circuit Breaker Pattern
 * Защита от каскадных сбоев при работе с внешними сервисами
 */

const DEFAULT_CONFIG = {
  failureThreshold: 5, // Количество ошибок до открытия circuit
  resetTimeout: 60000, // 60 секунд до попытки восстановления
  monitoringPeriod: 300000, // 5 минут для мониторинга
};

class CircuitBreaker {
  constructor(name, config = {}) {
    this.name = name;
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.successCount = 0;
    this.lastStateChange = Date.now();
  }

  /**
   * Выполнить операцию через circuit breaker
   */
  async execute(fn) {
    // Проверяем состояние circuit
    if (this.state === 'OPEN') {
      // Проверяем, можно ли попробовать восстановить
      if (Date.now() - this.lastStateChange > this.config.resetTimeout) {
        this.state = 'HALF_OPEN';
        this.successCount = 0;
        log.info({ circuit: this.name }, 'Circuit breaker переход в HALF_OPEN');
      } else {
        throw new Error(`Circuit breaker ${this.name} is OPEN`);
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  /**
   * Обработка успешного выполнения
   */
  onSuccess() {
    this.failureCount = 0;

    if (this.state === 'HALF_OPEN') {
      this.successCount++;
      // Если несколько успешных запросов подряд, закрываем circuit
      if (this.successCount >= 2) {
        this.state = 'CLOSED';
        this.lastStateChange = Date.now();
        log.info({ circuit: this.name }, 'Circuit breaker закрыт (CLOSED)');
      }
    }
  }

  /**
   * Обработка ошибки
   */
  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();

    if (this.state === 'HALF_OPEN') {
      // Если ошибка в HALF_OPEN, сразу открываем circuit
      this.state = 'OPEN';
      this.lastStateChange = Date.now();
      log.warn({ circuit: this.name, failureCount: this.failureCount }, 'Circuit breaker открыт (OPEN) из HALF_OPEN');
    } else if (this.failureCount >= this.config.failureThreshold) {
      this.state = 'OPEN';
      this.lastStateChange = Date.now();
      log.warn({ circuit: this.name, failureCount: this.failureCount }, 'Circuit breaker открыт (OPEN)');
    }
  }

  /**
   * Получить текущее состояние
   */
  getState() {
    return {
      state: this.state,
      failureCount: this.failureCount,
      lastFailureTime: this.lastFailureTime,
      successCount: this.successCount,
    };
  }

  /**
   * Сбросить состояние
   */
  reset() {
    this.state = 'CLOSED';
    this.failureCount = 0;
    this.successCount = 0;
    this.lastFailureTime = null;
    this.lastStateChange = Date.now();
    log.info({ circuit: this.name }, 'Circuit breaker сброшен');
  }
}

// Глобальные circuit breakers для разных сервисов
const circuitBreakers = new Map();

/**
 * Получить или создать circuit breaker для сервиса
 */
export function getCircuitBreaker(name, config) {
  if (!circuitBreakers.has(name)) {
    circuitBreakers.set(name, new CircuitBreaker(name, config));
  }
  return circuitBreakers.get(name);
}

/**
 * Выполнить операцию через circuit breaker
 */
export async function executeWithCircuitBreaker(name, fn, config) {
  const breaker = getCircuitBreaker(name, config);
  return breaker.execute(fn);
}

/**
 * Получить состояние всех circuit breakers
 */
export function getAllCircuitBreakerStates() {
  const states = {};
  circuitBreakers.forEach((breaker, name) => {
    states[name] = breaker.getState();
  });
  return states;
}
