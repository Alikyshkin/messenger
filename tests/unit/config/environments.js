import { DEFAULT_HTTP_PORT } from '../../../server/config/constants.js';

/**
 * Конфигурация окружений для тестов.
 */
export const environments = {
  test: {
    baseUrl: process.env.TEST_BASE_URL || 'http://127.0.0.1',
    wsUrl: process.env.TEST_WS_URL || 'ws://127.0.0.1',
    dbPath: process.env.MESSENGER_DB_PATH || ':memory:',
  },
  dev: {
    baseUrl: process.env.API_BASE_URL || `http://localhost:${DEFAULT_HTTP_PORT}`,
    wsUrl: process.env.WS_BASE_URL || `ws://localhost:${DEFAULT_HTTP_PORT}`,
  },
  stage: {
    baseUrl: process.env.API_BASE_URL || 'https://stage-api.example.com',
    wsUrl: process.env.WS_BASE_URL || 'wss://stage-api.example.com',
  },
};

export function getEnv(name = 'test') {
  return environments[name] || environments.test;
}
