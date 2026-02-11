/**
 * Утилита для синхронизации FTS5 индексов с основными таблицами
 * Вызывается после вставки/обновления сообщений
 */

import db from '../db.js';

/**
 * Синхронизирует FTS индекс для личных сообщений
 */
export function syncMessagesFTS(messageId) {
  try {
    // Используем INSERT OR REPLACE для SQLite (вместо ON CONFLICT DO UPDATE)
    db.prepare(`
      INSERT OR REPLACE INTO messages_fts(rowid, content)
      SELECT id, content FROM messages WHERE id = ?
    `).run(messageId);
  } catch (error) {
    // Игнорируем ошибки, если FTS таблица не создана
    if (!error.message.includes('no such table')) {
      console.error('FTS sync error:', error);
    }
  }
}

/**
 * Синхронизирует FTS индекс для групповых сообщений
 */
export function syncGroupMessagesFTS(messageId) {
  try {
    // Используем INSERT OR REPLACE для SQLite (вместо ON CONFLICT DO UPDATE)
    db.prepare(`
      INSERT OR REPLACE INTO group_messages_fts(rowid, content)
      SELECT id, content FROM group_messages WHERE id = ?
    `).run(messageId);
  } catch (error) {
    // Игнорируем ошибки, если FTS таблица не создана
    if (!error.message.includes('no such table')) {
      console.error('FTS sync error:', error);
    }
  }
}

/**
 * Инициализирует FTS индексы для существующих сообщений
 */
export function initFTSIndexes() {
  try {
    // Синхронизируем существующие личные сообщения
    // Используем INSERT OR IGNORE для SQLite (вместо ON CONFLICT DO NOTHING)
    db.prepare(`
      INSERT OR IGNORE INTO messages_fts(rowid, content)
      SELECT id, content FROM messages
    `).run();
    
    // Синхронизируем существующие групповые сообщения
    db.prepare(`
      INSERT OR IGNORE INTO group_messages_fts(rowid, content)
      SELECT id, content FROM group_messages
    `).run();
  } catch (error) {
    // Игнорируем ошибки, если FTS таблицы не созданы
    if (!error.message.includes('no such table')) {
      console.error('FTS init error:', error);
    }
  }
}
