import { defineConfig } from '@playwright/test';
import { TEST_PORTS } from '../../server/config/constants.js';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.resolve(__dirname, '../../server');
const testPort = process.env.PLAYWRIGHT_TEST_PORT || TEST_PORTS.PLAYWRIGHT_E2E;
const clientPort = process.env.PLAYWRIGHT_CLIENT_PORT || TEST_PORTS.PLAYWRIGHT_CLIENT;

// baseURL для тестов — Flutter web-клиент; API-сервер доступен через PLAYWRIGHT_SERVER_URL
process.env.PLAYWRIGHT_SERVER_URL = process.env.PLAYWRIGHT_SERVER_URL || `http://127.0.0.1:${testPort}`;

export default defineConfig({
  testDir: '.',
  timeout: 120000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: 'list',
  use: {
    baseURL: `http://127.0.0.1:${clientPort}`,
    // По умолчанию headless. Видимый браузер при PW_HEADED=1.
    headless: process.env.PW_HEADED !== '1',
    viewport: { width: 1280, height: 720 },
    trace: 'off',
    video: 'off',
  },
  webServer: {
    command: `node "${serverDir}/scripts/start-client-and-server.js"`,
    url: `http://127.0.0.1:${clientPort}`,
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  projects: [
    {
      name: 'e2e',
      testMatch: /\.e2e\.spec\.js$/,
    },
  ],
});
