import admin from 'firebase-admin';
import { log } from './logger.js';

let fcmEnabled = false;
let messaging = null;

/**
 * Инициализация Firebase Cloud Messaging
 */
export function initFCM() {
  const serviceAccountPath = process.env.FCM_SERVICE_ACCOUNT_PATH;
  const serviceAccountJson = process.env.FCM_SERVICE_ACCOUNT_JSON;
  
  if (!serviceAccountPath && !serviceAccountJson) {
    log.warn('FCM не настроен: отсутствует service account');
    return;
  }
  
  try {
    let serviceAccount;
    
    if (serviceAccountJson) {
      serviceAccount = JSON.parse(serviceAccountJson);
    } else {
      const fs = await import('fs');
      const serviceAccountData = fs.readFileSync(serviceAccountPath, 'utf8');
      serviceAccount = JSON.parse(serviceAccountData);
    }
    
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    
    messaging = admin.messaging();
    fcmEnabled = true;
    
    log.info('Firebase Cloud Messaging инициализирован');
  } catch (error) {
    log.error({ error }, 'Ошибка инициализации FCM');
    fcmEnabled = false;
  }
}

/**
 * Отправить push-уведомление одному устройству
 */
export async function sendToDevice(token, notification, data = {}) {
  if (!fcmEnabled || !messaging) {
    log.warn('FCM не доступен, уведомление не отправлено');
    return { success: false, error: 'FCM not enabled' };
  }
  
  if (!token) {
    return { success: false, error: 'Token is required' };
  }
  
  try {
    const message = {
      token,
      notification: {
        title: notification.title,
        body: notification.body,
        ...(notification.imageUrl && { imageUrl: notification.imageUrl }),
      },
      data: {
        ...data,
        // Преобразуем все значения в строки (требование FCM)
        ...Object.fromEntries(
          Object.entries(data).map(([key, value]) => [key, String(value)])
        ),
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'messenger_notifications',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };
    
    const response = await messaging.send(message);
    log.info({ token, messageId: response }, 'Push-уведомление отправлено');
    
    return { success: true, messageId: response };
  } catch (error) {
    log.error({ error, token }, 'Ошибка отправки push-уведомления');
    
    // Если токен недействителен, нужно удалить его из БД
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      return { success: false, error: 'invalid_token', shouldRemove: true };
    }
    
    return { success: false, error: error.message };
  }
}

/**
 * Отправить push-уведомление нескольким устройствам
 */
export async function sendToDevices(tokens, notification, data = {}) {
  if (!fcmEnabled || !messaging) {
    log.warn('FCM не доступен, уведомления не отправлены');
    return { success: false, error: 'FCM not enabled' };
  }
  
  if (!tokens || tokens.length === 0) {
    return { success: false, error: 'Tokens are required' };
  }
  
  // Удаляем дубликаты и невалидные токены
  const uniqueTokens = [...new Set(tokens)].filter(Boolean);
  
  if (uniqueTokens.length === 0) {
    return { success: false, error: 'No valid tokens' };
  }
  
  try {
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
        ...(notification.imageUrl && { imageUrl: notification.imageUrl }),
      },
      data: {
        ...data,
        ...Object.fromEntries(
          Object.entries(data).map(([key, value]) => [key, String(value)])
        ),
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'messenger_notifications',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };
    
    const response = await messaging.sendEachForMulticast({
      tokens: uniqueTokens,
      ...message,
    });
    
    log.info({
      total: uniqueTokens.length,
      success: response.successCount,
      failure: response.failureCount,
    }, 'Multicast push-уведомления отправлены');
    
    // Собираем невалидные токены для удаления
    const invalidTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        const error = resp.error;
        if (error?.code === 'messaging/invalid-registration-token' ||
            error?.code === 'messaging/registration-token-not-registered') {
          invalidTokens.push(uniqueTokens[idx]);
        }
      }
    });
    
    return {
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
      invalidTokens,
    };
  } catch (error) {
    log.error({ error }, 'Ошибка отправки multicast push-уведомлений');
    return { success: false, error: error.message };
  }
}

/**
 * Отправить уведомление о новом сообщении
 */
export async function notifyNewMessage(userId, message, sender) {
  // Получаем FCM токены пользователя из БД
  const db = (await import('../db.js')).default;
  const tokens = db.prepare(`
    SELECT fcm_token FROM user_fcm_tokens WHERE user_id = ? AND fcm_token IS NOT NULL
  `).all(userId).map(row => row.fcm_token);
  
  if (tokens.length === 0) {
    return { success: false, error: 'No FCM tokens found' };
  }
  
  const notification = {
    title: sender.display_name || sender.username,
    body: message.content || 'Новое сообщение',
    ...(message.attachment_url && { imageUrl: message.attachment_url }),
  };
  
  const data = {
    type: 'new_message',
    message_id: String(message.id),
    sender_id: String(sender.id),
    sender_name: sender.display_name || sender.username,
    content: message.content || '',
    chat_type: 'personal',
  };
  
  return await sendToDevices(tokens, notification, data);
}

/**
 * Отправить уведомление о новом групповом сообщении
 */
export async function notifyNewGroupMessage(groupId, message, sender, groupName) {
  const db = (await import('../db.js')).default;
  
  // Получаем всех участников группы кроме отправителя
  const members = db.prepare(`
    SELECT DISTINCT gm.user_id
    FROM group_members gm
    WHERE gm.group_id = ? AND gm.user_id != ?
  `).all(groupId, sender.id);
  
  if (members.length === 0) {
    return { success: false, error: 'No group members found' };
  }
  
  // Получаем FCM токены всех участников
  const userIds = members.map(m => m.user_id);
  const placeholders = userIds.map(() => '?').join(',');
  const tokens = db.prepare(`
    SELECT fcm_token FROM user_fcm_tokens 
    WHERE user_id IN (${placeholders}) AND fcm_token IS NOT NULL
  `).all(...userIds).map(row => row.fcm_token);
  
  if (tokens.length === 0) {
    return { success: false, error: 'No FCM tokens found' };
  }
  
  const notification = {
    title: groupName,
    body: `${sender.display_name || sender.username}: ${message.content || 'Новое сообщение'}`,
    ...(message.attachment_url && { imageUrl: message.attachment_url }),
  };
  
  const data = {
    type: 'new_group_message',
    message_id: String(message.id),
    group_id: String(groupId),
    sender_id: String(sender.id),
    sender_name: sender.display_name || sender.username,
    content: message.content || '',
    chat_type: 'group',
  };
  
  return await sendToDevices(tokens, notification, data);
}

/**
 * Проверить, включен ли FCM
 */
export function isEnabled() {
  return fcmEnabled;
}
