/**
 * Централизованная конфигурация приложения
 */

import 'dotenv/config';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import * as constants from './constants.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const config = {
  // Сервер
  port: parseInt(process.env.PORT || String(constants.DEFAULT_HTTP_PORT), 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  
  // База данных
  db: {
    path: process.env.MESSENGER_DB_PATH || join(__dirname, '../messenger.db'),
  },
  
  // JWT
  jwt: {
    secret: process.env.JWT_SECRET || constants.JWT_CONFIG.DEFAULT_SECRET,
    expiresIn: constants.JWT_CONFIG.EXPIRES_IN,
  },
  
  // CORS
  cors: {
    origins: process.env.CORS_ORIGINS 
      ? process.env.CORS_ORIGINS.split(',').map(origin => origin.trim())
      : [`http://localhost:${constants.DEFAULT_HTTP_PORT}`, 'http://localhost:8080', `http://127.0.0.1:${constants.DEFAULT_HTTP_PORT}`, 'http://127.0.0.1:8080'],
  },
  
  // Логирование
  logging: {
    level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
  },
  
  // SMTP (для отправки писем)
  smtp: {
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
    from: process.env.MAIL_FROM,
  },
  
  // Приложение
  app: {
    baseUrl: process.env.APP_BASE_URL || `http://localhost:${constants.DEFAULT_HTTP_PORT}`,
  },
  
  // Шифрование (для старых сообщений)
  encryption: {
    key: process.env.ENCRYPTION_KEY,
  },
  
  // OAuth провайдеры (опционально — если не заданы, кнопки входа скрыты)
  oauth: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    },
    vk: {
      appId: process.env.VK_APP_ID,
      clientSecret: process.env.VK_CLIENT_SECRET,
    },
    telegram: {
      botToken: process.env.TELEGRAM_BOT_TOKEN,
    },
  },
  
  // SMS для входа по телефону (опционально)
  sms: {
    provider: process.env.SMS_PROVIDER, // 'twilio' | 'custom' | пусто = отключено
    twilioAccountSid: process.env.TWILIO_ACCOUNT_SID,
    twilioAuthToken: process.env.TWILIO_AUTH_TOKEN,
    twilioFromNumber: process.env.TWILIO_FROM_NUMBER,
  },
  
  // Константы
  constants,
};

export default config;
