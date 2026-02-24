/**
 * Запуск сервера и Flutter web-клиента для Playwright E2E.
 * Сервер — на PLAYWRIGHT_TEST_PORT (по умолчанию 38473).
 * Клиент — на PLAYWRIGHT_CLIENT_PORT (по умолчанию 8765), API_BASE_URL указывает на сервер.
 * Процесс живёт до SIGINT/SIGTERM, затем завершает оба дочерних процесса.
 */
import { spawn } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverDir = join(__dirname, '..');
const clientDir = join(serverDir, '..', 'client');

const SERVER_PORT = parseInt(process.env.PLAYWRIGHT_TEST_PORT || '38473', 10);
const CLIENT_PORT = parseInt(process.env.PLAYWRIGHT_CLIENT_PORT || '8765', 10);
const SERVER_URL = `http://127.0.0.1:${SERVER_PORT}`;
const CLIENT_URL = `http://127.0.0.1:${CLIENT_PORT}`;

function waitForUrl(url, label, maxAttempts = 60, intervalMs = 1000) {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const tryFetch = () => {
      attempts++;
      fetch(url, { method: 'GET' })
        .then((r) => {
          if (r.ok) return resolve();
          if (attempts >= maxAttempts) reject(new Error(`${label} не ответил 200: ${r.status}`));
          setTimeout(tryFetch, intervalMs);
        })
        .catch((err) => {
          if (attempts >= maxAttempts) reject(new Error(`${label}: ${err.message}`));
          setTimeout(tryFetch, intervalMs);
        });
    };
    tryFetch();
  });
}

function log(msg) {
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${msg}`);
}

async function main() {
  process.env.NODE_ENV = 'test';
  process.env.MESSENGER_DB_PATH = ':memory:';
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';
  process.env.PORT = String(SERVER_PORT);
  const clientOrigin = `http://127.0.0.1:${CLIENT_PORT}`;
  process.env.CORS_ORIGINS = [process.env.CORS_ORIGINS, clientOrigin, `http://localhost:${CLIENT_PORT}`].filter(Boolean).join(',');

  const serverProc = spawn('node', ['scripts/start-test-server.js'], {
    cwd: serverDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, PORT: String(SERVER_PORT), CORS_ORIGINS: process.env.CORS_ORIGINS },
  });
  serverProc.stdout?.on('data', (d) => process.stdout.write(d));
  serverProc.stderr?.on('data', (d) => process.stderr.write(d));
  serverProc.on('error', (err) => {
    log(`Сервер не запустился: ${err.message}`);
    process.exit(1);
  });

  log(`Ожидание готовности сервера ${SERVER_URL}/ready ...`);
  await waitForUrl(`${SERVER_URL}/ready`, 'Сервер');
  log('Сервер готов.');

  const apiBaseUrl = SERVER_URL;
  const flutterProc = spawn(
    'flutter',
    [
      'run',
      '-d',
      'web-server',
      '--web-port',
      String(CLIENT_PORT),
      '--dart-define',
      `API_BASE_URL=${apiBaseUrl}`,
    ],
    {
      cwd: clientDir,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    }
  );
  flutterProc.stdout?.on('data', (d) => process.stdout.write(d));
  flutterProc.stderr?.on('data', (d) => process.stderr.write(d));
  flutterProc.on('error', (err) => {
    log(`Flutter не запустился: ${err.message}. Убедитесь, что Flutter установлен и в PATH.`);
    serverProc.kill('SIGTERM');
    process.exit(1);
  });

  log(`Ожидание готовности клиента ${CLIENT_URL} ...`);
  await waitForUrl(CLIENT_URL, 'Клиент', 90, 2000);
  log('Клиент готов. Можно запускать тесты (baseURL = ' + CLIENT_URL + ').');

  const killAll = (signal = 'SIGTERM') => {
    log('Завершение сервера и клиента...');
    serverProc.kill(signal);
    flutterProc.kill(signal);
  };

  process.on('SIGINT', () => {
    killAll();
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    killAll();
    process.exit(0);
  });

  // Держим процесс живым до SIGINT/SIGTERM (Playwright сам завершит команду после тестов)
  await new Promise(() => {});
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
