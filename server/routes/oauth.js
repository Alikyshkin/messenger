/**
 * OAuth и альтернативные методы входа (опциональные)
 * Работают только если в конфиге заданы соответствующие credentials
 */

import { Router } from 'express';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import db from '../db.js';
import config from '../config/index.js';
import { signToken } from '../auth.js';
import { authLimiter } from '../middleware/rateLimit.js';
import {
  validate,
  googleAuthSchema,
  vkAuthSchema,
  telegramAuthSchema,
  phoneSendCodeSchema,
  phoneVerifySchema,
} from '../middleware/validation.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { auditLog, AUDIT_EVENTS } from '../utils/auditLog.js';
import { log } from '../utils/logger.js';

const router = Router();

// Placeholder password для OAuth-пользователей (никогда не используется для входа)
const OAUTH_PLACEHOLDER_HASH = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 10);

function formatUser(user) {
  return {
    id: user.id,
    username: user.username,
    display_name: user.display_name || user.username,
    email: user.email || null,
  };
}

function findOrCreateOAuthUser(provider, providerId, displayName, email) {
  const col = `${provider}_id`;
  let user = db.prepare(`SELECT id, username, display_name, email FROM users WHERE ${col} = ?`).get(providerId);

  if (user) {
    return user;
  }

  // Генерируем уникальный username
  const baseUsername = `user_${provider}_${providerId}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
  let username = baseUsername;
  let suffix = 0;
  while (db.prepare('SELECT 1 FROM users WHERE username = ?').get(username)) {
    suffix += 1;
    username = `${baseUsername}_${suffix}`;
  }

  const result = db.prepare(
    `INSERT INTO users (username, display_name, password_hash, email, ${col}) VALUES (?, ?, ?, ?, ?)`
  ).run(
    username,
    displayName || username,
    OAUTH_PLACEHOLDER_HASH,
    email || null,
    providerId
  );

  user = db.prepare('SELECT id, username, display_name, email FROM users WHERE id = ?')
    .get(result.lastInsertRowid);
  return user;
}

// --- Google ---
router.post('/google', authLimiter, validate(googleAuthSchema), asyncHandler(async (req, res) => {
  const { clientId } = config.oauth?.google || {};
  if (!clientId) {
    return res.status(501).json({ error: 'Вход через Google не настроен' });
  }

  const { idToken } = req.validated;
  const client = new OAuth2Client(clientId);

  let ticket;
  try {
    ticket = await client.verifyIdToken({ idToken, audience: clientId });
  } catch (err) {
    log.warn({ err: err.message }, 'Google token verification failed');
    return res.status(401).json({ error: 'Недействительный токен Google' });
  }

  const payload = ticket.getPayload();
  const googleId = String(payload.sub);
  const displayName = payload.name || payload.email?.split('@')[0] || `user_${googleId}`;
  const email = payload.email || null;
  const avatarUrl = payload.picture || null;

  const user = findOrCreateOAuthUser('google', googleId, displayName, email);

  const token = signToken(user.id, user.username);
  auditLog(AUDIT_EVENTS.LOGIN, user.id, { provider: 'google', ip: req.ip });
  res.json({ user: formatUser(user), token });
}));

// --- VK ---
router.post('/vk', authLimiter, validate(vkAuthSchema), asyncHandler(async (req, res) => {
  const { appId, clientSecret } = config.oauth?.vk || {};
  if (!appId || !clientSecret) {
    return res.status(501).json({ error: 'Вход через VK не настроен' });
  }

  const { accessToken, userId } = req.validated;
  const vkId = String(userId);

  // Проверяем токен через VK API
  const vkUrl = `https://api.vk.com/method/users.get?access_token=${encodeURIComponent(accessToken)}&v=5.199&fields=photo_100`;
  const vkRes = await fetch(vkUrl);
  const vkData = await vkRes.json();

  if (!vkData.response || !Array.isArray(vkData.response) || vkData.response.length === 0) {
    log.warn({ vkData }, 'VK API returned invalid response');
    return res.status(401).json({ error: 'Недействительный токен VK' });
  }

  const vkUser = vkData.response[0];
  const displayName = [vkUser.first_name, vkUser.last_name].filter(Boolean).join(' ') || `vk_${vkId}`;
  const avatarUrl = vkUser.photo_100 || null;

  const user = findOrCreateOAuthUser('vk', vkId, displayName, null);

  const token = signToken(user.id, user.username);
  auditLog(AUDIT_EVENTS.LOGIN, user.id, { provider: 'vk', ip: req.ip });
  res.json({ user: formatUser(user), token });
}));

// --- Telegram ---
router.post('/telegram', authLimiter, validate(telegramAuthSchema), asyncHandler(async (req, res) => {
  const { botToken } = config.oauth?.telegram || {};
  if (!botToken) {
    return res.status(501).json({ error: 'Вход через Telegram не настроен' });
  }

  const data = req.body; // Используем raw body для проверки hash (значения должны быть как от Telegram)
  const { id, first_name, last_name, username: tgUsername, photo_url, auth_date, hash } = data;

  if (!id || !auth_date || !hash) {
    return res.status(400).json({ error: 'Неполные данные Telegram' });
  }

  // Проверка hash (https://core.telegram.org/widgets/login#checking-authorization)
  const checkData = Object.keys(data)
    .filter(k => k !== 'hash')
    .sort()
    .map(k => `${k}=${data[k]}`)
    .join('\n');
  const secretKey = crypto.createHash('sha256').update(botToken).digest();
  const computedHash = crypto.createHmac('sha256', secretKey).update(checkData).digest('hex');

  if (computedHash !== hash) {
    log.warn('Telegram hash verification failed');
    return res.status(401).json({ error: 'Недействительные данные Telegram' });
  }

  // Проверка срока действия (не старше 24 часов)
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - auth_date) > 86400) {
    return res.status(401).json({ error: 'Данные авторизации устарели' });
  }

  const telegramId = String(id);
  const displayName = [first_name, last_name].filter(Boolean).join(' ') || tgUsername || `tg_${telegramId}`;

  const user = findOrCreateOAuthUser('telegram', telegramId, displayName, null);

  const token = signToken(user.id, user.username);
  auditLog(AUDIT_EVENTS.LOGIN, user.id, { provider: 'telegram', ip: req.ip });
  res.json({ user: formatUser(user), token });
}));

// --- Телефон: отправка кода ---
router.post('/phone/send-code', authLimiter, validate(phoneSendCodeSchema), asyncHandler(async (req, res) => {
  const smsConfig = config.sms;
  if (!smsConfig?.provider || smsConfig.provider !== 'twilio') {
    return res.status(501).json({ error: 'Вход по телефону не настроен' });
  }

  const { phone } = req.validated;
  const normalizedPhone = phone.replace(/\D/g, '');
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const codeHash = crypto.createHash('sha256').update(code).digest('hex');
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString(); // 10 мин

  db.prepare('DELETE FROM phone_verification_codes WHERE phone = ?').run(normalizedPhone);
  db.prepare(
    'INSERT INTO phone_verification_codes (phone, code_hash, expires_at) VALUES (?, ?, ?)'
  ).run(normalizedPhone, codeHash, expiresAt);

  // Отправка SMS через Twilio
  try {
    const twilio = await import('twilio').catch(() => null);
    if (twilio && smsConfig.twilioAccountSid && smsConfig.twilioAuthToken) {
      const client = twilio.default(smsConfig.twilioAccountSid, smsConfig.twilioAuthToken);
      await client.messages.create({
        body: `Код для входа в Мессенджер: ${code}`,
        from: smsConfig.twilioFromNumber,
        to: `+${normalizedPhone}`,
      });
    } else {
      // Режим разработки: логируем код
      log.info({ phone: normalizedPhone, code }, 'Phone verification code (dev mode, SMS not sent)');
    }
  } catch (err) {
    log.error({ err, phone: normalizedPhone }, 'Failed to send SMS');
    return res.status(500).json({ error: 'Не удалось отправить SMS' });
  }

  res.json({ message: 'Код отправлен' });
}));

// --- Телефон: верификация и вход ---
router.post('/phone/verify', authLimiter, validate(phoneVerifySchema), asyncHandler(async (req, res) => {
  const { phone, code } = req.validated;
  const normalizedPhone = phone.replace(/\D/g, '');
  const codeHash = crypto.createHash('sha256').update(code).digest('hex');

  const row = db.prepare(
    'SELECT id FROM phone_verification_codes WHERE phone = ? AND code_hash = ? AND expires_at > datetime(\'now\')'
  ).get(normalizedPhone, codeHash);

  if (!row) {
    return res.status(401).json({ error: 'Неверный или истёкший код' });
  }

  db.prepare('DELETE FROM phone_verification_codes WHERE id = ?').run(row.id);

  let user = db.prepare('SELECT id, username, display_name, email FROM users WHERE phone = ?').get(normalizedPhone);

  if (!user) {
    const username = `phone_${normalizedPhone}`;
    const result = db.prepare(
      'INSERT INTO users (username, display_name, password_hash, phone) VALUES (?, ?, ?, ?)'
    ).run(`phone_${normalizedPhone}`, `+${normalizedPhone}`, OAUTH_PLACEHOLDER_HASH, normalizedPhone);
    user = db.prepare('SELECT id, username, display_name, email FROM users WHERE id = ?')
      .get(result.lastInsertRowid);
  }

  const token = signToken(user.id, user.username);
  auditLog(AUDIT_EVENTS.LOGIN, user.id, { provider: 'phone', ip: req.ip });
  res.json({ user: formatUser(user), token });
}));

// Эндпоинт для проверки доступных методов входа (клиент может скрыть ненастроенные)
router.get('/providers', (req, res) => {
  const oauth = config.oauth || {};
  const sms = config.sms || {};
  res.json({
    google: !!(oauth.google?.clientId),
    vk: !!(oauth.vk?.appId && oauth.vk?.clientSecret),
    telegram: !!(oauth.telegram?.botToken),
    phone: sms.provider === 'twilio' && !!(sms.twilioAccountSid && sms.twilioAuthToken),
  });
});

export default router;
