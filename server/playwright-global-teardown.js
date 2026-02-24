import { existsSync, readFileSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const defaultOutFile = join(__dirname, '.playwright-server.json');

export default async function globalTeardown() {
  const outFile = process.env.__PLAYWRIGHT_SERVER_FILE || defaultOutFile;
  if (!existsSync(outFile)) return;
  try {
    const { pid } = JSON.parse(readFileSync(outFile, 'utf8'));
    if (pid) process.kill(pid, 'SIGTERM');
  } catch (_) {}
  try {
    unlinkSync(outFile);
  } catch (_) {}
}
