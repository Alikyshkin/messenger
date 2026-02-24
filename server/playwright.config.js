import { defineConfig } from '@playwright/test';

// Порт отдельный от E2E (38473), в верхнем диапазоне чтобы реже конфликтовать с другими процессами
const testPort = process.env.PLAYWRIGHT_TEST_PORT || 48473;

export default defineConfig({
  testDir: './tests/playwright',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : 4,
  reporter: 'list',
  use: {
    baseURL: `http://127.0.0.1:${testPort}`,
    extraHTTPHeaders: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  },
  webServer: {
    command: `NODE_ENV=test MESSENGER_DB_PATH=:memory: JWT_SECRET=test-secret PORT=${testPort} node scripts/start-test-server.js`,
    url: `http://127.0.0.1:${testPort}/ready`,
    reuseExistingServer: !process.env.CI,
    timeout: 20000,
  },
  projects: [{ name: 'api', testMatch: /.*(?<!\.e2e)\.spec\.js$/ }],
});
