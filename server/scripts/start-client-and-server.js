/**
 * Запуск сервера и Flutter web-клиента для Playwright E2E.
 * Сервер — на PLAYWRIGHT_TEST_PORT (по умолчанию 38473).
 * Клиент — на PLAYWRIGHT_CLIENT_PORT (по умолчанию 8765).
 *
 * Клиент подаётся из предварительно собранного build/web (flutter build web).
 * Если build/web не существует, запускает flutter run -d web-server (медленнее).
 */
import { spawn } from 'child_process';
import { createServer } from 'http';
import { join, dirname, extname } from 'path';
import { fileURLToPath } from 'url';
import { readFileSync, existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverDir = join(__dirname, '..');
const clientDir = join(serverDir, '..', 'client');
const buildDir = join(clientDir, 'build', 'web');

const SERVER_PORT = parseInt(process.env.PLAYWRIGHT_TEST_PORT || '38473', 10);
const CLIENT_PORT = parseInt(process.env.PLAYWRIGHT_CLIENT_PORT || '8765', 10);
const SERVER_URL = `http://127.0.0.1:${SERVER_PORT}`;

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

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
};

function servePrebuiltClient() {
  return new Promise((resolve) => {
    const httpServer = createServer((req, res) => {
      let filePath = join(buildDir, req.url === '/' ? 'index.html' : req.url);
      if (!existsSync(filePath) || filePath.indexOf(buildDir) !== 0) {
        filePath = join(buildDir, 'index.html');
      }
      try {
        const data = readFileSync(filePath);
        const ext = extname(filePath);
        res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
        res.end(data);
      } catch {
        res.writeHead(404);
        res.end('Not found');
      }
    });
    httpServer.listen(CLIENT_PORT, '127.0.0.1', () => {
      log(`Клиент (pre-built) запущен на http://127.0.0.1:${CLIENT_PORT}`);
      resolve(httpServer);
    });
  });
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

  let clientServer;
  let flutterProc;

  if (existsSync(buildDir)) {
    log('Найден pre-built клиент, запускаем статический сервер...');
    clientServer = await servePrebuiltClient();
  } else {
    log('Pre-built клиент не найден, запускаем flutter run...');
    const apiBaseUrl = SERVER_URL;
    flutterProc = spawn(
      'flutter',
      ['run', '-d', 'web-server', '--web-port', String(CLIENT_PORT), '--dart-define', `API_BASE_URL=${apiBaseUrl}`],
      { cwd: clientDir, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env } }
    );
    flutterProc.stdout?.on('data', (d) => process.stdout.write(d));
    flutterProc.stderr?.on('data', (d) => process.stderr.write(d));
    flutterProc.on('error', (err) => {
      log(`Flutter не запустился: ${err.message}`);
      serverProc.kill('SIGTERM');
      process.exit(1);
    });

    log(`Ожидание готовности клиента http://127.0.0.1:${CLIENT_PORT} ...`);
    await waitForUrl(`http://127.0.0.1:${CLIENT_PORT}`, 'Клиент', 90, 2000);
  }

  log(`Клиент готов. baseURL = http://127.0.0.1:${CLIENT_PORT}`);

  const killAll = (signal = 'SIGTERM') => {
    log('Завершение...');
    serverProc.kill(signal);
    if (flutterProc) flutterProc.kill(signal);
    if (clientServer) clientServer.close();
  };

  process.on('SIGINT', () => { killAll(); process.exit(0); });
  process.on('SIGTERM', () => { killAll(); process.exit(0); });

  await new Promise(() => {});
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
