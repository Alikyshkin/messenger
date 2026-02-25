import { defineConfig } from '@playwright/test';
import { TEST_PORTS } from './config/constants.js';

const testPort = process.env.PLAYWRIGHT_TEST_PORT || TEST_PORTS.PLAYWRIGHT_E2E;
const clientPort = process.env.PLAYWRIGHT_CLIENT_PORT || TEST_PORTS.PLAYWRIGHT_CLIENT;

// При запуске Playwright (npm run test:playwright:e2e) поднимаются и client, и server.
// baseURL — Flutter web-клиент в браузере; API — на testPort (для запросов из тестов).
process.env.PLAYWRIGHT_SERVER_URL = process.env.PLAYWRIGHT_SERVER_URL || `http://127.0.0.1:${testPort}`;

export default defineConfig({
  testDir: './tests/playwright',
  timeout: 60000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : 4,
  reporter: 'list',
  use: {
    baseURL: `http://127.0.0.1:${clientPort}`,
    // По умолчанию headless — без мелькания окна. Видимый браузер только при PW_HEADED=1.
    headless: process.env.PW_HEADED !== '1',
    viewport: { width: 1280, height: 720 },
    trace: 'off',
    video: 'off',
  },
  webServer: {
    command: `node scripts/start-client-and-server.js`,
    url: `http://127.0.0.1:${clientPort}`,
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  projects: [
    {
      name: 'e2e',
      testMatch: /.*\.e2e\.spec\.js$/,
    },
  ],
});
