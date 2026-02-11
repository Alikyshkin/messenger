import Database from 'better-sqlite3';
import { readdirSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { log } from '../utils/logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Таблица для отслеживания применённых миграций
 */
function ensureMigrationsTable(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

/**
 * Получить список применённых миграций
 */
function getAppliedMigrations(db) {
  const rows = db.prepare('SELECT version FROM schema_migrations ORDER BY version').all();
  return new Set(rows.map(r => r.version));
}

/**
 * Получить список файлов миграций
 */
function getMigrationFiles() {
  const migrationsDir = join(__dirname, 'versions');
  try {
    const files = readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .map(f => {
        const match = f.match(/^(\d+)_(.+)\.sql$/);
        if (!match) {
          log.warn(`Пропущен файл миграции с неверным форматом имени: ${f}`);
          return null;
        }
        return {
          version: parseInt(match[1], 10),
          name: match[2],
          filename: f,
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.version - b.version);
    return files;
  } catch (error) {
    if (error.code === 'ENOENT') {
      log.warn(`Директория миграций не найдена: ${migrationsDir}`);
      return [];
    }
    throw error;
  }
}

/**
 * Применить миграцию
 */
function applyMigration(db, migration) {
  const migrationsDir = join(__dirname, 'versions');
  const filePath = join(migrationsDir, migration.filename);
  
  log.info(`Применение миграции ${migration.version}: ${migration.name}`);
  
  const sql = readFileSync(filePath, 'utf-8');
  
  // Выполняем миграцию в транзакции
  const transaction = db.transaction(() => {
    db.exec(sql);
    db.prepare('INSERT INTO schema_migrations (version, name) VALUES (?, ?)')
      .run(migration.version, migration.name);
  });
  
  transaction();
  
  log.info(`Миграция ${migration.version} применена успешно`);
}

/**
 * Применить все неприменённые миграции
 */
export function runMigrations(dbPath) {
  const db = new Database(dbPath);
  
  try {
    ensureMigrationsTable(db);
    const applied = getAppliedMigrations(db);
    const files = getMigrationFiles();
    
    const pending = files.filter(f => !applied.has(f.version));
    
    if (pending.length === 0) {
      log.info('Все миграции уже применены');
      return;
    }
    
    log.info(`Найдено ${pending.length} неприменённых миграций`);
    
    for (const migration of pending) {
      applyMigration(db, migration);
    }
    
    log.info('Все миграции применены успешно');
  } catch (error) {
    log.error({ error }, 'Ошибка при применении миграций');
    throw error;
  } finally {
    db.close();
  }
}

/**
 * Получить текущую версию схемы БД
 */
export function getCurrentVersion(dbPath) {
  const db = new Database(dbPath);
  
  try {
    ensureMigrationsTable(db);
    const row = db.prepare('SELECT MAX(version) as version FROM schema_migrations').get();
    return row?.version || 0;
  } finally {
    db.close();
  }
}
