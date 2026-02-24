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
  
  // Для миграции 007 проверяем структуру таблиц перед выполнением SQL
  if (migration.version === 7) {
    const transaction = db.transaction(() => {
      try {
        // Проверяем, существуют ли таблицы и какая у них структура
        const tablesExist = db.prepare(`
          SELECT name FROM sqlite_master 
          WHERE type='table' AND name IN ('group_polls', 'group_poll_votes')
        `).all();
        
        const hasGroupPolls = tablesExist.some(t => t.name === 'group_polls');
        const hasGroupPollVotes = tablesExist.some(t => t.name === 'group_poll_votes');
        
        if (!hasGroupPolls && !hasGroupPollVotes) {
          // Таблиц нет, создаем с правильной структурой
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
        } else {
          // Таблицы существуют, проверяем структуру и исправляем при необходимости
          if (hasGroupPolls) {
            const groupPollsInfo = db.prepare(`PRAGMA table_info(group_polls)`).all();
            const hasGroupMessageId = groupPollsInfo.some(col => col.name === 'group_message_id');
            const hasMessageId = groupPollsInfo.some(col => col.name === 'message_id');
            
            if (hasMessageId && !hasGroupMessageId) {
              // Старая структура, исправляем
              log.warn('Таблица group_polls имеет старую структуру, исправляем');
              try {
                // Проверяем, есть ли колонка multiple
                const hasMultiple = groupPollsInfo.some(col => col.name === 'multiple');
                
                // Проверяем данные перед копированием
                const rowCount = db.prepare('SELECT COUNT(*) as count FROM group_polls').get();
                log.info(`Найдено ${rowCount.count} записей в таблице group_polls для миграции`);
                
                // Проверяем на дубликаты message_id
                const duplicates = db.prepare(`
                  SELECT message_id, COUNT(*) as cnt 
                  FROM group_polls 
                  WHERE message_id IS NOT NULL 
                  GROUP BY message_id 
                  HAVING cnt > 1
                `).all();
                
                if (duplicates.length > 0) {
                  log.warn(`Найдено ${duplicates.length} дубликатов message_id в group_polls, оставляем только первую запись для каждого`);
                  // Удаляем дубликаты, оставляя только первую запись
                  db.exec(`
                    DELETE FROM group_polls 
                    WHERE id NOT IN (
                      SELECT MIN(id) 
                      FROM group_polls 
                      GROUP BY message_id
                    )
                  `);
                }
                
                // Проверяем, существует ли таблица group_messages
                const groupMessagesExists = db.prepare(`
                  SELECT name FROM sqlite_master 
                  WHERE type='table' AND name='group_messages'
                `).get();
                
                if (!groupMessagesExists) {
                  log.warn('Таблица group_messages не существует, создаем group_polls без внешнего ключа');
                  db.exec(`
                    CREATE TABLE group_polls_temp (
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      group_message_id INTEGER NOT NULL UNIQUE,
                      question TEXT NOT NULL,
                      options TEXT NOT NULL,
                      multiple INTEGER DEFAULT 0
                    );
                  `);
                } else {
                  // Создаем временную таблицу с внешним ключом
                  db.exec(`
                    CREATE TABLE group_polls_temp (
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      group_message_id INTEGER NOT NULL UNIQUE,
                      question TEXT NOT NULL,
                      options TEXT NOT NULL,
                      multiple INTEGER DEFAULT 0,
                      FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE
                    );
                  `);
                }
                
                // Копируем данные с учетом наличия колонки multiple
                // Исключаем записи с NULL message_id и используем DISTINCT для избежания дубликатов
                log.info('Копируем данные из старой таблицы group_polls');
                try {
                  if (hasMultiple) {
                    db.exec(`
                      INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
                      SELECT DISTINCT id, message_id, question, options, COALESCE(multiple, 0) 
                      FROM group_polls 
                      WHERE message_id IS NOT NULL;
                    `);
                  } else {
                    db.exec(`
                      INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
                      SELECT DISTINCT id, message_id, question, options, 0 
                      FROM group_polls 
                      WHERE message_id IS NOT NULL;
                    `);
                  }
                  log.info('Данные успешно скопированы');
                } catch (insertError) {
                  log.error({ 
                    error: insertError, 
                    message: insertError.message,
                    code: insertError.code 
                  }, 'Ошибка при копировании данных из group_polls');
                  // Пытаемся вставить без UNIQUE ограничения, если есть дубликаты
                  db.exec('DROP TABLE group_polls_temp');
                  if (!groupMessagesExists) {
                    db.exec(`
                      CREATE TABLE group_polls_temp (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        group_message_id INTEGER NOT NULL,
                        question TEXT NOT NULL,
                        options TEXT NOT NULL,
                        multiple INTEGER DEFAULT 0
                      );
                    `);
                  } else {
                    db.exec(`
                      CREATE TABLE group_polls_temp (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        group_message_id INTEGER NOT NULL,
                        question TEXT NOT NULL,
                        options TEXT NOT NULL,
                        multiple INTEGER DEFAULT 0,
                        FOREIGN KEY (group_message_id) REFERENCES group_messages(id) ON DELETE CASCADE
                      );
                    `);
                  }
                  // Вставляем только уникальные записи
                  if (hasMultiple) {
                    db.exec(`
                      INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
                      SELECT MIN(id), message_id, question, options, COALESCE(multiple, 0) 
                      FROM group_polls 
                      WHERE message_id IS NOT NULL
                      GROUP BY message_id;
                    `);
                  } else {
                    db.exec(`
                      INSERT INTO group_polls_temp (id, group_message_id, question, options, multiple)
                      SELECT MIN(id), message_id, question, options, 0 
                      FROM group_polls 
                      WHERE message_id IS NOT NULL
                      GROUP BY message_id;
                    `);
                  }
                  log.warn('Данные скопированы без UNIQUE ограничения из-за дубликатов');
                }
                
                // Удаляем старую таблицу и переименовываем новую
                log.info('Удаляем старую таблицу и переименовываем новую');
                db.exec(`
                  DROP TABLE group_polls;
                  ALTER TABLE group_polls_temp RENAME TO group_polls;
                `);
                
                // Добавляем UNIQUE ограничение, если его нет
                try {
                  db.exec(`
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_group_polls_message_id ON group_polls(group_message_id);
                  `);
                } catch (idxError) {
                  log.warn({ error: idxError }, 'Не удалось создать UNIQUE индекс на group_message_id');
                }
                
                log.info('Таблица group_polls успешно исправлена');
              } catch (fixError) {
                log.error({ 
                  error: fixError, 
                  message: fixError.message,
                  code: fixError.code,
                  stack: fixError.stack 
                }, 'Ошибка при исправлении таблицы group_polls');
                throw fixError;
              }
            }
          }
          
          if (hasGroupPollVotes) {
            const groupPollVotesInfo = db.prepare(`PRAGMA table_info(group_poll_votes)`).all();
            const hasGroupPollId = groupPollVotesInfo.some(col => col.name === 'group_poll_id');
            const hasPollId = groupPollVotesInfo.some(col => col.name === 'poll_id');
            
            if (hasPollId && !hasGroupPollId) {
              // Старая структура, исправляем
              log.warn('Таблица group_poll_votes имеет старую структуру, исправляем');
              try {
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
                
                // Копируем данные из старой таблицы
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
                
                log.info('Таблица group_poll_votes успешно исправлена');
              } catch (fixError) {
                log.error({ error: fixError, message: fixError.message }, 'Ошибка при исправлении таблицы group_poll_votes');
                throw fixError;
              }
            } else if (hasGroupPollId) {
              // Правильная структура, просто создаем индексы если их нет
              db.exec(`
                CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll ON group_poll_votes(group_poll_id);
                CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
                CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(group_poll_id, user_id);
              `);
            }
          }
        }
        
        db.prepare('INSERT INTO schema_migrations (version, name) VALUES (?, ?)')
          .run(migration.version, migration.name);
      } catch (error) {
        log.error({ 
          error, 
          message: error.message, 
          code: error.code,
          stack: error.stack 
        }, 'Ошибка при применении миграции 007');
        throw error;
      }
    });
    
    transaction();
    log.info(`Миграция ${migration.version} применена успешно`);
    return;
  }
  
  // Миграция 008: добавляем sender_public_key — делаем идемпотентной (колонка может уже быть из db.js)
  if (migration.version === 8) {
    const transaction = db.transaction(() => {
      const hasColumn = db.prepare(
        "SELECT 1 FROM pragma_table_info('messages') WHERE name='sender_public_key'"
      ).get();
      if (!hasColumn) {
        db.exec('ALTER TABLE messages ADD COLUMN sender_public_key TEXT');
      }
      db.exec(
        "UPDATE messages SET sender_public_key = (SELECT public_key FROM users WHERE id = messages.sender_id) WHERE sender_public_key IS NULL"
      );
      db.prepare('INSERT INTO schema_migrations (version, name) VALUES (?, ?)')
        .run(migration.version, migration.name);
    });
    transaction();
    log.info(`Миграция ${migration.version} применена успешно`);
    return;
  }

  // Для остальных миграций выполняем SQL как обычно
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
 * Применить все неприменённые миграции к уже открытому подключению (не закрывает db).
 * Используется для :memory: чтобы миграции и приложение работали с одной БД.
 */
export function runMigrationsOnDb(db) {
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
}

/**
 * Применить все неприменённые миграции
 */
export function runMigrations(dbPath) {
  const db = new Database(dbPath);
  try {
    runMigrationsOnDb(db);
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
