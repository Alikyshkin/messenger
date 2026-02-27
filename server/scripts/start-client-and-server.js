/**
 * Запуск сервера и Flutter web-клиента для Playwright E2E.
 * Сервер — на PLAYWRIGHT_TEST_PORT (по умолчанию из config/constants.js).
 * Клиент — на PLAYWRIGHT_CLIENT_PORT, API_BASE_URL указывает на сервер.
 *
 * Клиент подаётся из предварительно собранного build/web (flutter build web).
 * Если build/web не существует, запускает flutter run -d web-server (медленнее).
 * Процесс живёт до SIGINT/SIGTERM, затем завершает оба дочерних процесса.
 */
import { spawn } from 'child_process';
import { createServer } from 'http';
import { join, dirname, extname } from 'path';
import { fileURLToPath } from 'url';
import { readFileSync, existsSync } from 'fs';
import { TEST_PORTS } from '../config/constants.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverDir = join(__dirname, '..');
const clientDir = join(serverDir, '..', 'client');
const buildDir = join(clientDir, 'build', 'web');

const SERVER_PORT = parseInt(process.env.PLAYWRIGHT_TEST_PORT || String(TEST_PORTS.PLAYWRIGHT_E2E), 10);
const CLIENT_PORT = parseInt(process.env.PLAYWRIGHT_CLIENT_PORT || String(TEST_PORTS.PLAYWRIGHT_CLIENT), 10);
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

// API-пути, которые проксируются на тестовый сервер
const API_PATH_PREFIXES = [
  '/auth/',
  '/users/',
  '/contacts/',
  '/messages/',
  '/groups/',
  '/chats/',
  '/polls/',
  '/sync/',
  '/search/',
  '/gdpr/',
  '/notifications/',
];
const API_EXACT_PATHS = new Set(['/health', '/ready', '/live', '/metrics']);

function isApiPath(pathname) {
  if (API_EXACT_PATHS.has(pathname)) return true;
  return API_PATH_PREFIXES.some((p) => pathname.startsWith(p));
}

async function proxyToApi(req, res, targetBase) {
  const url = `${targetBase}${req.url}`;
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;

  try {
    const apiRes = await fetch(url, {
      method: req.method,
      headers: Object.fromEntries(
        Object.entries(req.headers).filter(([k]) => k !== 'host')
      ),
      body: body && body.length ? body : undefined,
      redirect: 'manual',
    });
    res.writeHead(apiRes.status, Object.fromEntries(apiRes.headers));
    const buf = await apiRes.arrayBuffer();
    res.end(Buffer.from(buf));
  } catch (err) {
    log(`Proxy error for ${req.url}: ${err.message}`);
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Proxy error', detail: err.message }));
  }
}

function servePrebuiltClient(apiServerUrl) {
  return new Promise((resolve) => {
    const httpServer = createServer(async (req, res) => {
      const pathname = (req.url || '/').split('?')[0].split('#')[0];

      // Проксируем API-запросы на тестовый сервер
      if (isApiPath(pathname)) {
        await proxyToApi(req, res, apiServerUrl);
        return;
      }

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
      log(`Клиент (pre-built) запущен на http://127.0.0.1:${CLIENT_PORT}, API проксируется на ${apiServerUrl}`);
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
    clientServer = await servePrebuiltClient(SERVER_URL);
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
