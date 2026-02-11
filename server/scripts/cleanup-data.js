#!/usr/bin/env node

/**
 * Скрипт для очистки старых данных согласно политике хранения
 * Использование: node scripts/cleanup-data.js
 */

import { runDataRetentionCleanup } from '../utils/dataRetention.js';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Настраиваем путь к БД
process.env.MESSENGER_DB_PATH = process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db');

console.log('Запуск очистки данных...');

try {
  const results = runDataRetentionCleanup();
  
  console.log('\nРезультаты очистки:');
  console.log(`- Сообщения: ${results.messages}`);
  console.log(`- Групповые сообщения: ${results.groupMessages}`);
  console.log(`- Audit logs: ${results.auditLogs}`);
  console.log(`- Токены сброса пароля: ${results.resetTokens}`);
  console.log(`- Read receipts: ${results.readReceipts}`);
  console.log(`\nВсего удалено записей: ${Object.values(results).reduce((sum, count) => sum + count, 0)}`);
  
  process.exit(0);
} catch (error) {
  console.error('Ошибка при очистке данных:', error);
  process.exit(1);
}
