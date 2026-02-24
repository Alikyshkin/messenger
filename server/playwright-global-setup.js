import { spawn } from 'child_process';
import { existsSync, readFileSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverDir = __dirname;
const outFile = join(serverDir, '.playwright-server.json');

export default async function globalSetup() {
  const child = spawn('node', ['scripts/start-test-server.js'], {
    cwd: serverDir,
    env: { ...process.env, NODE_ENV: 'test', MESSENGER_DB_PATH: ':memory:', JWT_SECRET: 'test-secret' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  // Ждём появления файла с портом (макс. 10 сек)
  for (let i = 0; i < 100; i++) {
    await new Promise((r) => setTimeout(r, 100));
    if (existsSync(outFile)) break;
    if (child.exitCode != null) {
      const stderr = (child.stderr && child.stderr.read) ? child.stderr.read() : '';
      throw new Error(`Test server exited with ${child.exitCode}. ${stderr}`);
    }
  }
  if (!existsSync(outFile)) throw new Error('Test server did not write .playwright-server.json');

  const data = JSON.parse(readFileSync(outFile, 'utf8'));
  const baseURL = `http://127.0.0.1:${data.port}`;

  process.env.__PLAYWRIGHT_SERVER_PID = String(data.pid);
  process.env.__PLAYWRIGHT_SERVER_FILE = outFile;

  return { BASE_URL: baseURL };
}
