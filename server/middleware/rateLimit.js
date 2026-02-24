import rateLimit from 'express-rate-limit';

const skipInTest = () => process.env.NODE_ENV === 'test';

// Общий лимит для всех API запросов
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 100, // максимум 100 запросов с одного IP
  message: { error: 'Слишком много запросов, попробуйте позже' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

// Строгий лимит для аутентификации (защита от брутфорса)
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 5, // максимум 5 попыток входа
  message: { error: 'Слишком много попыток входа, попробуйте через 15 минут' },
  skipSuccessfulRequests: true, // не считать успешные запросы
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

// Лимит для отправки сообщений (защита от спама)
export const messageLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 минута
  max: 30, // максимум 30 сообщений в минуту
  message: { error: 'Слишком много сообщений, подождите немного' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

// Лимит для регистрации
export const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 час
  max: 3, // максимум 3 регистрации с одного IP в час
  message: { error: 'Слишком много попыток регистрации, попробуйте позже' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

// Лимит для сброса пароля
export const passwordResetLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 час
  max: 3, // максимум 3 запроса на сброс пароля в час
  message: { error: 'Слишком много запросов на сброс пароля, попробуйте позже' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});

// Лимит для загрузки файлов
export const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 20, // максимум 20 загрузок за 15 минут
  message: { error: 'Слишком много загрузок, подождите немного' },
  standardHeaders: true,
  legacyHeaders: false,
  skip: skipInTest,
});
