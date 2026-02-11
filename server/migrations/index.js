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
    try {
      db.exec(sql);
    } catch (error) {
      // Для миграции 007 обрабатываем ошибки отдельно, так как она может падать
      // если таблицы не существуют или имеют старую структуру
      if (migration.version === 7 && error.code === 'SQLITE_ERROR' && error.message.includes('no such table')) {
        // Таблицы нет, просто создаем пустые таблицы с правильной структурой
        log.warn('Таблицы group_polls/group_poll_votes не существуют, создаем с правильной структурой');
        db.exec(`
          CREATE TABLE IF NOT EXISTS group_polls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_message_id INTEGER NOT NULL UNIQUE,
            question TEXT NOT NULL,
            options TEXT NOT NULL,
            multiple INTEGER DEFAULT 0,
            FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE
          );
          CREATE TABLE IF NOT EXISTS group_poll_votes (
            group_poll_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            option_index INTEGER NOT NULL,
            PRIMARY KEY (group_poll_id, user_id, option_index),
            FOREIGN KEY (group_poll_id) REFERENCES group_polls(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          );
          CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
          CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
          CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
        `);
      } else if (migration.version === 7 && error.code === 'SQLITE_ERROR' && error.message.includes('no such column: group_poll_id')) {
        // Таблица существует со старой структурой, исправляем её
        log.warn('Таблица group_poll_votes имеет старую структуру, исправляем');
        try {
          // Создаем временную таблицу с правильной структурой
          db.exec(`
            CREATE TABLE group_poll_votes_temp (
              group_poll_id INTEGER NOT NULL,
              user_id INTEGER NOT NULL,
              option_index INTEGER NOT NULL,
              PRIMARY KEY (group_poll_id, user_id, option_index),
              FOREIGN KEY (group_poll_id) REFERENCES group_polls(id) ON DELETE CASCADE,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
          `);
          
          // Копируем данные из старой таблицы, используя poll_id
          db.exec(`
            INSERT INTO group_poll_votes_temp (group_poll_id, user_id, option_index)
            SELECT poll_id, user_id, option_index FROM group_poll_votes;
          `);
          
          // Удаляем старую таблицу и переименовываем новую
          db.exec(`
            DROP TABLE group_poll_votes;
            ALTER TABLE group_poll_votes_temp RENAME TO group_poll_votes;
            CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
            CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
            CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
          `);
        } catch (fixError) {
          log.error({ error: fixError }, 'Ошибка при исправлении структуры таблицы');
          throw fixError;
        }
      } else {
        throw error; // Пробрасываем другие ошибки дальше
      }
    }
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
