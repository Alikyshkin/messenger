import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { log } from '../utils/logger.js';
import { auditLog, AUDIT_EVENTS } from '../utils/auditLog.js';
import { delPattern, CacheKeys } from '../utils/cache.js';

const router = Router();
router.use(authMiddleware);

/**
 * @swagger
 * /gdpr/delete-account:
 *   delete:
 *     summary: Удалить аккаунт и все данные пользователя (GDPR)
 *     tags: [GDPR]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Аккаунт успешно удалён
 *       401:
 *         description: Не авторизован
 */
router.delete('/delete-account', asyncHandler(async (req, res) => {
  const userId = req.user.userId;
  
  log.info({ userId }, 'GDPR: Starting account deletion');
  
  // Удаляем все данные пользователя в транзакции
  const transaction = db.transaction(() => {
    // Удаляем сообщения пользователя
    db.prepare('DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?').run(userId, userId);
    
    // Удаляем групповые сообщения пользователя
    db.prepare('DELETE FROM group_messages WHERE sender_id = ?').run(userId);
    
    // Удаляем контакты
    db.prepare('DELETE FROM contacts WHERE user_id = ? OR contact_id = ?').run(userId, userId);
    
    // Удаляем из групп
    db.prepare('DELETE FROM group_members WHERE user_id = ?').run(userId);
    
    // Удаляем реакции
    db.prepare('DELETE FROM message_reactions WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM group_message_reactions WHERE user_id = ?').run(userId);
    
    // Удаляем голоса в опросах
    db.prepare('DELETE FROM poll_votes WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM group_poll_votes WHERE user_id = ?').run(userId);
    
    // Удаляем заявки в друзья
    db.prepare('DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?').run(userId, userId);
    
    // Удаляем FCM токены
    db.prepare('DELETE FROM user_fcm_tokens WHERE user_id = ?').run(userId);
    
    // Удаляем токены сброса пароля
    db.prepare('DELETE FROM password_reset_tokens WHERE user_id = ?').run(userId);
    
    // Удаляем audit logs (опционально, можно оставить анонимизированными)
    // db.prepare('DELETE FROM audit_logs WHERE user_id = ?').run(userId);
    
    // Удаляем пользователя (CASCADE удалит связанные данные)
    db.prepare('DELETE FROM users WHERE id = ?').run(userId);
  });
  
  transaction();
  
  // Очищаем кэш
  await delPattern(`user:${userId}:*`);
  await delPattern(`*:${userId}:*`);
  
  // Audit log (перед удалением пользователя)
  auditLog(AUDIT_EVENTS.ACCOUNT_DELETE, userId, {
    ip: req.ip || req.connection?.remoteAddress,
    userAgent: req.get('user-agent'),
  });
  
  log.info({ userId }, 'GDPR: Account deleted successfully');
  
  res.json({ message: 'Аккаунт и все данные успешно удалены' });
}));

/**
 * @swagger
 * /gdpr/export-data:
 *   get:
 *     summary: Экспортировать все данные пользователя (GDPR)
 *     tags: [GDPR]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Данные пользователя в JSON формате
 */
router.get('/export-data', asyncHandler(async (req, res) => {
  const userId = req.user.userId;
  
  // Используем существующий endpoint экспорта
  // Это уже реализовано в routes/export.js
  // Просто редиректим или возвращаем ссылку
  
  res.json({
    message: 'Используйте /export/json для экспорта данных',
    url: '/export/json',
  });
}));

export default router;
