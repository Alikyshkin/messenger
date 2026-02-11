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
    db.prepare(`
      INSERT INTO messages_fts(rowid, content)
      SELECT id, content FROM messages WHERE id = ?
      ON CONFLICT(rowid) DO UPDATE SET content = excluded.content
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
    db.prepare(`
      INSERT INTO group_messages_fts(rowid, content)
      SELECT id, content FROM group_messages WHERE id = ?
      ON CONFLICT(rowid) DO UPDATE SET content = excluded.content
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
    db.prepare(`
      INSERT INTO messages_fts(rowid, content)
      SELECT id, content FROM messages
      ON CONFLICT(rowid) DO NOTHING
    `).run();
    
    // Синхронизируем существующие групповые сообщения
    db.prepare(`
      INSERT INTO group_messages_fts(rowid, content)
      SELECT id, content FROM group_messages
      ON CONFLICT(rowid) DO NOTHING
    `).run();
  } catch (error) {
    // Игнорируем ошибки, если FTS таблицы не созданы
    if (!error.message.includes('no such table')) {
      console.error('FTS init error:', error);
    }
  }
}
