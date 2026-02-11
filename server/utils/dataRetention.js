import db from '../db.js';
import { log } from './logger.js';
import { unlinkSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Политики хранения данных (в днях)
const RETENTION_POLICIES = {
  messages: parseInt(process.env.MESSAGE_RETENTION_DAYS || '365', 10), // 1 год по умолчанию
  auditLogs: parseInt(process.env.AUDIT_LOG_RETENTION_DAYS || '90', 10), // 90 дней
  resetTokens: parseInt(process.env.RESET_TOKEN_RETENTION_DAYS || '7', 10), // 7 дней
  readReceipts: parseInt(process.env.READ_RECEIPT_RETENTION_DAYS || '180', 10), // 180 дней
};

/**
 * Удалить старые сообщения согласно политике хранения
 */
export function cleanupOldMessages() {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_POLICIES.messages);
    
    // Получаем сообщения для удаления
    const messagesToDelete = db.prepare(`
      SELECT id, attachment_path FROM messages 
      WHERE created_at < ?
    `).all(cutoffDate.toISOString());
    
    // Удаляем файлы вложений
    messagesToDelete.forEach(msg => {
      if (msg.attachment_path) {
        const filePath = join(__dirname, '../uploads', msg.attachment_path);
        try {
          if (existsSync(filePath)) {
            unlinkSync(filePath);
          }
        } catch (error) {
          log.warn({ error, filePath }, 'Failed to delete attachment file');
        }
      }
    });
    
    // Удаляем сообщения из БД
    const result = db.prepare(`
      DELETE FROM messages 
      WHERE created_at < ?
    `).run(cutoffDate.toISOString());
    
    log.info({ 
      deleted: result.changes,
      cutoffDate: cutoffDate.toISOString(),
    }, 'Cleaned up old messages');
    
    return result.changes;
  } catch (error) {
    log.error({ error }, 'Failed to cleanup old messages');
    return 0;
  }
}

/**
 * Удалить старые групповые сообщения
 */
export function cleanupOldGroupMessages() {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_POLICIES.messages);
    
    // Получаем сообщения для удаления
    const messagesToDelete = db.prepare(`
      SELECT id, attachment_path FROM group_messages 
      WHERE created_at < ?
    `).all(cutoffDate.toISOString());
    
    // Удаляем файлы вложений
    messagesToDelete.forEach(msg => {
      if (msg.attachment_path) {
        const filePath = join(__dirname, '../uploads', msg.attachment_path);
        try {
          if (existsSync(filePath)) {
            unlinkSync(filePath);
          }
        } catch (error) {
          log.warn({ error, filePath }, 'Failed to delete group attachment file');
        }
      }
    });
    
    // Удаляем сообщения из БД
    const result = db.prepare(`
      DELETE FROM group_messages 
      WHERE created_at < ?
    `).run(cutoffDate.toISOString());
    
    log.info({ 
      deleted: result.changes,
      cutoffDate: cutoffDate.toISOString(),
    }, 'Cleaned up old group messages');
    
    return result.changes;
  } catch (error) {
    log.error({ error }, 'Failed to cleanup old group messages');
    return 0;
  }
}

/**
 * Удалить старые audit logs
 */
export function cleanupOldAuditLogs() {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_POLICIES.auditLogs);
    
    const result = db.prepare(`
      DELETE FROM audit_logs 
      WHERE created_at < ?
    `).run(cutoffDate.toISOString());
    
    log.info({ 
      deleted: result.changes,
      cutoffDate: cutoffDate.toISOString(),
    }, 'Cleaned up old audit logs');
    
    return result.changes;
  } catch (error) {
    log.error({ error }, 'Failed to cleanup old audit logs');
    return 0;
  }
}

/**
 * Удалить истёкшие токены сброса пароля
 */
export function cleanupExpiredResetTokens() {
  try {
    const result = db.prepare(`
      DELETE FROM password_reset_tokens 
      WHERE expires_at < datetime('now')
    `).run();
    
    log.info({ deleted: result.changes }, 'Cleaned up expired reset tokens');
    
    return result.changes;
  } catch (error) {
    log.error({ error }, 'Failed to cleanup expired reset tokens');
    return 0;
  }
}

/**
 * Удалить старые read receipts (прочитанные сообщения)
 */
export function cleanupOldReadReceipts() {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_POLICIES.readReceipts);
    
    // Удаляем старые read_at метки (оставляем только недавние)
    const result = db.prepare(`
      UPDATE messages 
      SET read_at = NULL 
      WHERE read_at IS NOT NULL AND read_at < ?
    `).run(cutoffDate.toISOString());
    
    log.info({ 
      updated: result.changes,
      cutoffDate: cutoffDate.toISOString(),
    }, 'Cleaned up old read receipts');
    
    return result.changes;
  } catch (error) {
    log.error({ error }, 'Failed to cleanup old read receipts');
    return 0;
  }
}

/**
 * Выполнить все операции очистки данных
 */
export function runDataRetentionCleanup() {
  log.info('Starting data retention cleanup');
  
  const results = {
    messages: cleanupOldMessages(),
    groupMessages: cleanupOldGroupMessages(),
    auditLogs: cleanupOldAuditLogs(),
    resetTokens: cleanupExpiredResetTokens(),
    readReceipts: cleanupOldReadReceipts(),
  };
  
  const total = Object.values(results).reduce((sum, count) => sum + count, 0);
  
  log.info({ results, total }, 'Data retention cleanup completed');
  
  return results;
}
