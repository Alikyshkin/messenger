#!/usr/bin/env node

/**
 * Скрипт для ручного применения миграций
 * Использование: node scripts/migrate.js [path/to/database.db]
 */

import { runMigrations, getCurrentVersion } from '../migrations/index.js';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const dbPath = process.argv[2] || process.env.MESSENGER_DB_PATH || join(__dirname, '../../messenger.db');

console.log(`Применение миграций для базы данных: ${dbPath}`);

try {
  const currentVersion = getCurrentVersion(dbPath);
  console.log(`Текущая версия схемы: ${currentVersion || 0}`);
  
  runMigrations(dbPath);
  
  const newVersion = getCurrentVersion(dbPath);
  console.log(`Новая версия схемы: ${newVersion || 0}`);
  
  if (currentVersion === newVersion) {
    console.log('Все миграции уже применены');
  } else {
    console.log(`Применено миграций: ${newVersion - currentVersion}`);
  }
} catch (error) {
  console.error('Ошибка при применении миграций:', error);
  process.exit(1);
}
