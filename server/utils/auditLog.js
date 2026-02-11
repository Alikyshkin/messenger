import db from '../db.js';
import { log } from './logger.js';

/**
 * Audit Log - логирование важных действий пользователей
 * Для соответствия требованиям безопасности и compliance
 */

const AUDIT_EVENTS = {
  LOGIN: 'login',
  LOGIN_FAILED: 'login_failed',
  LOGOUT: 'logout',
  REGISTER: 'register',
  PASSWORD_CHANGE: 'password_change',
  PASSWORD_RESET: 'password_reset',
  PROFILE_UPDATE: 'profile_update',
  CONTACT_ADD: 'contact_add',
  CONTACT_DELETE: 'contact_delete',
  MESSAGE_SEND: 'message_send',
  MESSAGE_DELETE: 'message_delete',
  GROUP_CREATE: 'group_create',
  GROUP_UPDATE: 'group_update',
  GROUP_DELETE: 'group_delete',
  GROUP_MEMBER_ADD: 'group_member_add',
  GROUP_MEMBER_REMOVE: 'group_member_remove',
  DATA_EXPORT: 'data_export',
  ACCOUNT_DELETE: 'account_delete',
  ACCOUNT_LOCKED: 'account_locked',
};

/**
 * Создать запись в audit log
 */
export function auditLog(event, userId, details = {}) {
  try {
    db.prepare(`
      INSERT INTO audit_logs (event_type, user_id, ip_address, user_agent, details, created_at)
      VALUES (?, ?, ?, ?, ?, datetime('now'))
    `).run(
      event,
      userId || null,
      details.ip || null,
      details.userAgent || null,
      JSON.stringify(details),
    );
  } catch (error) {
    // Логируем ошибку, но не прерываем выполнение
    log.error({ error, event, userId }, 'Failed to write audit log');
  }
}

/**
 * Получить audit logs для пользователя
 */
export function getUserAuditLogs(userId, limit = 100, offset = 0) {
  try {
    const logs = db.prepare(`
      SELECT id, event_type, ip_address, user_agent, details, created_at
      FROM audit_logs
      WHERE user_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `).all(userId, limit, offset);
    
    return logs.map(log => ({
      ...log,
      details: JSON.parse(log.details || '{}'),
    }));
  } catch (error) {
    log.error({ error, userId }, 'Failed to get audit logs');
    return [];
  }
}

/**
 * Получить audit logs по типу события
 */
export function getAuditLogsByEvent(eventType, limit = 100, offset = 0) {
  try {
    const logs = db.prepare(`
      SELECT id, event_type, user_id, ip_address, user_agent, details, created_at
      FROM audit_logs
      WHERE event_type = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `).all(eventType, limit, offset);
    
    return logs.map(log => ({
      ...log,
      details: JSON.parse(log.details || '{}'),
    }));
  } catch (error) {
    log.error({ error, eventType }, 'Failed to get audit logs by event');
    return [];
  }
}

/**
 * Middleware для автоматического логирования запросов
 */
export function auditMiddleware(req, res, next) {
  // Сохраняем оригинальный метод end для отслеживания завершения запроса
  const originalEnd = res.end;
  res.end = function(...args) {
    // Логируем только важные события после успешного выполнения
    if (res.statusCode >= 200 && res.statusCode < 300) {
      const event = getEventFromRoute(req);
      if (event && req.user?.userId) {
        auditLog(event, req.user.userId, {
          ip: req.ip || req.connection?.remoteAddress,
          userAgent: req.get('user-agent'),
          method: req.method,
          path: req.path,
          statusCode: res.statusCode,
        });
      }
    }
    
    originalEnd.apply(this, args);
  };
  
  next();
}

/**
 * Определить тип события из маршрута
 */
function getEventFromRoute(req) {
  const { method, path } = req;
  
  if (path.startsWith('/auth/login') && method === 'POST') {
    return AUDIT_EVENTS.LOGIN;
  }
  if (path.startsWith('/auth/register') && method === 'POST') {
    return AUDIT_EVENTS.REGISTER;
  }
  if (path.startsWith('/auth/change-password') && method === 'POST') {
    return AUDIT_EVENTS.PASSWORD_CHANGE;
  }
  if (path.startsWith('/auth/reset-password') && method === 'POST') {
    return AUDIT_EVENTS.PASSWORD_RESET;
  }
  if (path.startsWith('/users/me') && method === 'PATCH') {
    return AUDIT_EVENTS.PROFILE_UPDATE;
  }
  if (path.startsWith('/contacts') && method === 'POST') {
    return AUDIT_EVENTS.CONTACT_ADD;
  }
  if (path.startsWith('/contacts') && method === 'DELETE') {
    return AUDIT_EVENTS.CONTACT_DELETE;
  }
  if (path.startsWith('/messages') && method === 'POST') {
    return AUDIT_EVENTS.MESSAGE_SEND;
  }
  if (path.startsWith('/messages') && method === 'DELETE') {
    return AUDIT_EVENTS.MESSAGE_DELETE;
  }
  if (path.startsWith('/groups') && method === 'POST' && !path.includes('/messages')) {
    return AUDIT_EVENTS.GROUP_CREATE;
  }
  if (path.startsWith('/groups') && method === 'PATCH') {
    return AUDIT_EVENTS.GROUP_UPDATE;
  }
  if (path.startsWith('/groups') && method === 'DELETE') {
    return AUDIT_EVENTS.GROUP_DELETE;
  }
  if (path.startsWith('/export') && method === 'GET') {
    return AUDIT_EVENTS.DATA_EXPORT;
  }
  
  return null;
}

export { AUDIT_EVENTS };
