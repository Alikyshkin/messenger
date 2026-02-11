#!/usr/bin/env node

/**
 * Скрипт для автоматического бэкапа базы данных мессенджера
 * Использование: node scripts/backup-db.js [путь_к_базе] [путь_к_бэкапам]
 */

import Database from 'better-sqlite3';
import { mkdirSync, existsSync, readdirSync, statSync, unlinkSync } from 'fs';
import { join, dirname } from 'path';
import { createGzip } from 'zlib';
import { createWriteStream, createReadStream } from 'fs';
import { pipeline } from 'stream/promises';

const DB_PATH = process.argv[2] || 'server/messenger.db';
const BACKUP_DIR = process.argv[3] || 'backups';
const KEEP_DAYS = 30;

// Создаём директорию для бэкапов
if (!existsSync(BACKUP_DIR)) {
  mkdirSync(BACKUP_DIR, { recursive: true });
}

// Проверяем существование базы данных
if (!existsSync(DB_PATH)) {
  console.error(`Ошибка: База данных не найдена: ${DB_PATH}`);
  process.exit(1);
}

// Имя файла бэкапа с датой и временем
const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const backupFile = join(BACKUP_DIR, `messenger_${timestamp}.db`);
const backupFileGz = `${backupFile}.gz`;

try {
  // Открываем базу данных
  const db = new Database(DB_PATH, { readonly: true });
  
  // Создаём временный файл для бэкапа
  const tempBackup = join(BACKUP_DIR, `temp_${Date.now()}.db`);
  const tempDb = new Database(tempBackup);
  
  // Выполняем бэкап
  db.backup(tempDb)
    .then(() => {
      db.close();
      tempDb.close();
      
      // Сжимаем бэкап
      return pipeline(
        createReadStream(tempBackup),
        createGzip(),
        createWriteStream(backupFileGz)
      );
    })
    .then(() => {
      // Удаляем временный файл
      unlinkSync(tempBackup);
      
      console.log(`Бэкап создан: ${backupFileGz}`);
      
      // Удаляем старые бэкапы
      const files = readdirSync(BACKUP_DIR)
        .filter(f => f.startsWith('messenger_') && f.endsWith('.db.gz'))
        .map(f => ({
          name: f,
          path: join(BACKUP_DIR, f),
          mtime: statSync(join(BACKUP_DIR, f)).mtime,
        }));
      
      const now = Date.now();
      const keepTime = KEEP_DAYS * 24 * 60 * 60 * 1000;
      
      let deletedCount = 0;
      files.forEach(file => {
        if (now - file.mtime.getTime() > keepTime) {
          unlinkSync(file.path);
          deletedCount++;
        }
      });
      
      if (deletedCount > 0) {
        console.log(`Удалено старых бэкапов: ${deletedCount}`);
      }
      
      // Выводим список последних бэкапов
      console.log('\nПоследние бэкапы:');
      const recentFiles = files
        .filter(f => now - f.mtime.getTime() <= keepTime)
        .sort((a, b) => b.mtime - a.mtime)
        .slice(0, 5);
      
      recentFiles.forEach(file => {
        const size = (statSync(file.path).size / 1024 / 1024).toFixed(2);
        console.log(`  ${file.name} (${size} MB)`);
      });
    })
    .catch(err => {
      console.error('Ошибка при создании бэкапа:', err);
      process.exit(1);
    });
} catch (error) {
  console.error('Ошибка:', error.message);
  process.exit(1);
}
