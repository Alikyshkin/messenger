import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { validate } from '../middleware/validation.js';
import Joi from 'joi';
import { sendToDevice, isEnabled } from '../utils/pushNotifications.js';
import { log } from '../utils/logger.js';
import { asyncHandler } from '../middleware/errorHandler.js';

const router = Router();
router.use(authMiddleware);

const registerTokenSchema = Joi.object({
  fcm_token: Joi.string().required().min(1),
  device_id: Joi.string().optional(),
  device_name: Joi.string().optional(),
  platform: Joi.string().valid('android', 'ios', 'web').optional(),
});

const unregisterTokenSchema = Joi.object({
  fcm_token: Joi.string().required().min(1),
});

/**
 * @swagger
 * /push/register:
 *   post:
 *     summary: Зарегистрировать FCM токен для push-уведомлений
 *     tags: [Push Notifications]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - fcm_token
 *             properties:
 *               fcm_token:
 *                 type: string
 *               device_id:
 *                 type: string
 *               device_name:
 *                 type: string
 *               platform:
 *                 type: string
 *                 enum: [android, ios, web]
 *     responses:
 *       200:
 *         description: Токен зарегистрирован
 *       400:
 *         description: Ошибка валидации
 */
router.post('/register', validate(registerTokenSchema), asyncHandler(async (req, res) => {
  if (!isEnabled()) {
    return res.status(503).json({ error: 'Push-уведомления не настроены' });
  }
  
  const { fcm_token, device_id, device_name, platform } = req.validated;
  const userId = req.user.userId;
  
  try {
    // Проверяем, существует ли уже такой токен
    const existing = db.prepare('SELECT id FROM user_fcm_tokens WHERE user_id = ? AND fcm_token = ?')
      .get(userId, fcm_token);
    
    if (existing) {
      // Обновляем информацию о токене
      db.prepare(`
        UPDATE user_fcm_tokens 
        SET device_id = ?, device_name = ?, platform = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(device_id || null, device_name || null, platform || null, existing.id);
    } else {
      // Добавляем новый токен
      db.prepare(`
        INSERT INTO user_fcm_tokens (user_id, fcm_token, device_id, device_name, platform)
        VALUES (?, ?, ?, ?, ?)
      `).run(userId, fcm_token, device_id || null, device_name || null, platform || null);
    }
    
    log.info({ userId, device_id, platform }, 'FCM токен зарегистрирован');
    res.json({ success: true });
  } catch (error) {
    log.error({ error, userId }, 'Ошибка регистрации FCM токена');
    res.status(500).json({ error: 'Ошибка регистрации токена' });
  }
}));

/**
 * @swagger
 * /push/unregister:
 *   post:
 *     summary: Удалить FCM токен
 *     tags: [Push Notifications]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - fcm_token
 *             properties:
 *               fcm_token:
 *                 type: string
 *     responses:
 *       200:
 *         description: Токен удалён
 */
router.post('/unregister', validate(unregisterTokenSchema), asyncHandler(async (req, res) => {
  const { fcm_token } = req.validated;
  const userId = req.user.userId;
  
  try {
    db.prepare('DELETE FROM user_fcm_tokens WHERE user_id = ? AND fcm_token = ?')
      .run(userId, fcm_token);
    
    log.info({ userId }, 'FCM токен удалён');
    res.json({ success: true });
  } catch (error) {
    log.error({ error, userId }, 'Ошибка удаления FCM токена');
    res.status(500).json({ error: 'Ошибка удаления токена' });
  }
}));

/**
 * @swagger
 * /push/test:
 *   post:
 *     summary: Отправить тестовое push-уведомление
 *     tags: [Push Notifications]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Тестовое уведомление отправлено
 *       503:
 *         description: Push-уведомления не настроены
 */
router.post('/test', asyncHandler(async (req, res) => {
  if (!isEnabled()) {
    return res.status(503).json({ error: 'Push-уведомления не настроены' });
  }
  
  const userId = req.user.userId;
  
  // Получаем первый токен пользователя
  const tokenRow = db.prepare('SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? LIMIT 1')
    .get(userId);
  
  if (!tokenRow || !tokenRow.fcm_token) {
    return res.status(404).json({ error: 'FCM токен не найден. Зарегистрируйте токен через /push/register' });
  }
  
  const result = await sendToDevice(
    tokenRow.fcm_token,
    {
      title: 'Тестовое уведомление',
      body: 'Это тестовое push-уведомление от мессенджера',
    },
    {
      type: 'test',
      timestamp: String(Date.now()),
    }
  );
  
  if (result.success) {
    res.json({ success: true, messageId: result.messageId });
  } else {
    res.status(500).json({ error: result.error });
  }
}));

export default router;
