/**
 * Запуск сервера для Playwright E2E.
 * Если задан PORT — слушает на нём (для Playwright webServer).
 * Иначе — на случайном порту и пишет port/pid в .playwright-server.json (для globalSetup).
 */
process.env.NODE_ENV = 'test';
process.env.MESSENGER_DB_PATH = ':memory:';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

import { writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { server } from '../index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const outFile = join(__dirname, '../.playwright-server.json');
const port = parseInt(process.env.PORT || '0', 10) || 0;

server.listen(port, '127.0.0.1', () => {
  const actualPort = server.address().port;
  if (!port) writeFileSync(outFile, JSON.stringify({ port: actualPort, pid: process.pid }));
});

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
