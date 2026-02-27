import { defineConfig } from '@playwright/test';
import { TEST_PORTS } from '../../server/config/constants.js';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.resolve(__dirname, '../../server');
const testPort = process.env.PLAYWRIGHT_TEST_PORT || TEST_PORTS.PLAYWRIGHT_API;

export default defineConfig({
  testDir: '.',
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
    command: `NODE_ENV=test MESSENGER_DB_PATH=:memory: JWT_SECRET=test-secret PORT=${testPort} node "${serverDir}/scripts/start-test-server.js"`,
    url: `http://127.0.0.1:${testPort}/ready`,
    reuseExistingServer: !process.env.CI,
    timeout: 20000,
  },
  projects: [{ name: 'api', testMatch: /\.spec\.js$/ }],
});
