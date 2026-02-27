/**
 * Юнит-тесты middleware fileValidation: MIME, размер, угрозы (исполняемые файлы).
 */
import { describe, it, before, after } from 'node:test';
import { strict as assert } from 'node:assert';
import { writeFileSync, unlinkSync, mkdirSync, existsSync, readdirSync, rmdirSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import {
  validateFileMimeType,
  validateFileSize,
  scanFileForThreats,
  validateFile,
} from '../../server/middleware/fileValidation.js';

const testDir = join(tmpdir(), `messenger-filevalidation-${Date.now()}`);

before(() => {
  if (!existsSync(testDir)) mkdirSync(testDir, { recursive: true });
});

after(() => {
  try {
    for (const f of readdirSync(testDir)) unlinkSync(join(testDir, f));
    rmdirSync(testDir);
  } catch (_) {}
});

describe('validateFileMimeType', () => {
  it('принимает JPEG по magic bytes', async () => {
    const path = join(testDir, 'x.jpg');
    const jpegMagic = Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x01, 0x02]);
    writeFileSync(path, jpegMagic);
    const result = await validateFileMimeType(path);
    assert.strictEqual(result.valid, true);
    assert.ok(result.mime);
    unlinkSync(path);
  });

  it('отклоняет неразрешённый тип по расширению когда magic неизвестен', async () => {
    const path = join(testDir, 'x.exe');
    writeFileSync(path, 'MZ'); // PE start
    const result = await validateFileMimeType(path);
    assert.strictEqual(result.valid, false);
    assert.ok(result.error);
    unlinkSync(path);
  });
});

describe('validateFileSize', () => {
  it('принимает файл в пределах лимита', async () => {
    const path = join(testDir, 'small.txt');
    writeFileSync(path, 'hello');
    const result = await validateFileSize(path, 1000);
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.size, 5);
    unlinkSync(path);
  });

  it('отклоняет файл больше лимита', async () => {
    const path = join(testDir, 'big.txt');
    writeFileSync(path, Buffer.alloc(2000));
    const result = await validateFileSize(path, 1000);
    assert.strictEqual(result.valid, false);
    assert.ok(result.error);
    unlinkSync(path);
  });
});

describe('scanFileForThreats', () => {
  it('отклоняет PE (Windows executable)', async () => {
    const path = join(testDir, 'pe.bin');
    writeFileSync(path, Buffer.from([0x4d, 0x5a, 0x00, 0x00]));
    const result = await scanFileForThreats(path);
    assert.strictEqual(result.valid, false);
    assert.ok(result.error?.includes('PE'));
    unlinkSync(path);
  });

  it('отклоняет ELF', async () => {
    const path = join(testDir, 'elf.bin');
    writeFileSync(path, Buffer.from([0x7f, 0x45, 0x4c, 0x46]));
    const result = await scanFileForThreats(path);
    assert.strictEqual(result.valid, false);
    assert.ok(result.error?.includes('ELF'));
    unlinkSync(path);
  });

  it('принимает безопасный файл', async () => {
    const path = join(testDir, 'safe.txt');
    writeFileSync(path, 'plain text');
    const result = await scanFileForThreats(path);
    assert.strictEqual(result.valid, true);
    unlinkSync(path);
  });
});

describe('validateFile', () => {
  it('возвращает valid: true для маленького JPEG', async () => {
    const path = join(testDir, 'img.jpg');
    const jpegMagic = Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x01, 0x02]);
    writeFileSync(path, jpegMagic);
    const result = await validateFile(path, 10 * 1024 * 1024);
    assert.strictEqual(result.valid, true);
    assert.ok(result.mime);
    assert.ok(result.size !== undefined);
    unlinkSync(path);
  });

  it('возвращает valid: false при превышении размера', async () => {
    const path = join(testDir, 'big.jpg');
    const jpegMagic = Buffer.from([0xff, 0xd8, 0xff]);
    writeFileSync(path, Buffer.concat([jpegMagic, Buffer.alloc(2000)]));
    const result = await validateFile(path, 100);
    assert.strictEqual(result.valid, false);
    unlinkSync(path);
  });
});
