import Joi from 'joi';
import zxcvbn from 'zxcvbn';
import { VALIDATION_LIMITS, ALLOWED_REACTION_EMOJIS } from '../config/constants.js';

// Middleware для валидации запросов
export const validate = (schema) => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,
      stripUnknown: true,
    });

    if (error) {
      const errors = error.details.map((detail) => detail.message);
      return res.status(400).json({ error: errors.join('; ') });
    }

    req.validated = value;
    next();
  };
};

// Схемы валидации для аутентификации
export const registerSchema = Joi.object({
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required()
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
      'string.min': `Имя пользователя минимум ${VALIDATION_LIMITS.USERNAME_MIN_LENGTH} символа`,
      'string.max': `Имя пользователя максимум ${VALIDATION_LIMITS.USERNAME_MAX_LENGTH} символов`,
    }),
  password: Joi.string().min(VALIDATION_LIMITS.PASSWORD_MIN_LENGTH).max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH).required()
    .messages({
      'string.min': `Пароль минимум ${VALIDATION_LIMITS.PASSWORD_MIN_LENGTH} символов`,
      'string.max': `Пароль максимум ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
  displayName: Joi.string().trim().max(VALIDATION_LIMITS.DISPLAY_NAME_MAX_LENGTH).allow('').optional(),
  email: Joi.string().email().trim().lowercase().max(255).optional().allow('', null),
});

export const loginSchema = Joi.object({
  username: Joi.string().trim().required(),
  password: Joi.string().required(),
});

export const forgotPasswordSchema = Joi.object({
  email: Joi.string().email().trim().lowercase().required()
    .messages({
      'string.email': 'Некорректный формат email',
    }),
});

export const resetPasswordSchema = Joi.object({
  token: Joi.string().required(),
  newPassword: Joi.string().min(VALIDATION_LIMITS.PASSWORD_MIN_LENGTH).max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH).required()
    .messages({
      'string.min': `Пароль минимум ${VALIDATION_LIMITS.PASSWORD_MIN_LENGTH} символов`,
      'string.max': `Пароль максимум ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
});

export const changePasswordSchema = Joi.object({
  currentPassword: Joi.string().required(),
  newPassword: Joi.string().min(VALIDATION_LIMITS.PASSWORD_MIN_LENGTH).max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH).required()
    .messages({
      'string.min': `Пароль минимум ${VALIDATION_LIMITS.PASSWORD_MIN_LENGTH} символов`,
      'string.max': `Пароль максимум ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
});

// Схемы для пользователей
export const updateUserSchema = Joi.object({
  display_name: Joi.string().trim().max(VALIDATION_LIMITS.DISPLAY_NAME_MAX_LENGTH).allow('').optional(),
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).optional()
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
    }),
  bio: Joi.string().trim().max(VALIDATION_LIMITS.BIO_MAX_LENGTH).allow('').optional(),
  email: Joi.string().email().trim().lowercase().max(255).allow('', null).optional(),
  birthday: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional().allow('', null)
    .messages({
      'string.pattern.base': 'День рождения в формате ГГГГ-ММ-ДД',
    }),
  phone: Joi.string().pattern(/^\d{10,15}$/).optional().allow('', null)
    .messages({
      'string.pattern.base': 'Некорректный номер телефона',
    }),
  public_key: Joi.string().max(500).allow('', null).optional(),
});

// Схемы для сообщений
export const sendMessageSchema = Joi.object({
  receiver_id: Joi.number().integer().positive().required(),
  content: Joi.string().trim().max(VALIDATION_LIMITS.MESSAGE_MAX_LENGTH).allow('').optional(),
  type: Joi.string().valid('text', 'poll').optional(),
  question: Joi.when('type', {
    is: 'poll',
    then: Joi.string().trim().min(1).max(VALIDATION_LIMITS.POLL_QUESTION_MAX_LENGTH).required(),
    otherwise: Joi.optional(),
  }),
  options: Joi.when('type', {
    is: 'poll',
    then: Joi.array().items(Joi.string().trim().max(VALIDATION_LIMITS.POLL_OPTION_MAX_LENGTH)).min(VALIDATION_LIMITS.POLL_MIN_OPTIONS).max(VALIDATION_LIMITS.POLL_MAX_OPTIONS).required(),
    otherwise: Joi.optional(),
  }),
  multiple: Joi.when('type', {
    is: 'poll',
    then: Joi.boolean().optional(),
    otherwise: Joi.optional(),
  }),
  reply_to_id: Joi.number().integer().positive().optional().allow(null),
  is_forwarded: Joi.boolean().optional(),
  forward_from_sender_id: Joi.when('is_forwarded', {
    is: true,
    then: Joi.number().integer().positive().optional(),
    otherwise: Joi.optional(),
  }),
  forward_from_display_name: Joi.when('is_forwarded', {
    is: true,
    then: Joi.string().trim().max(128).optional(),
    otherwise: Joi.optional(),
  }),
}).custom((value, helpers) => {
  // Проверка: должно быть либо content, либо файл, либо опрос
  if (!value.content && !value.type && !helpers.state.ancestors[0]?.files?.length) {
    return helpers.error('any.required', { message: 'content или файл обязательны' });
  }
  return value;
});

// Схемы для контактов
export const addContactSchema = Joi.object({
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required(),
});

// Схемы для групп
export const createGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH).required()
    .messages({
      'string.min': 'Название группы обязательно',
      'string.max': `Название группы максимум ${VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH} символов`,
    }),
  member_ids: Joi.array().items(Joi.number().integer().positive()).optional(),
});

export const updateGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH).optional(),
});

export const addGroupMemberSchema = Joi.object({
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required(),
});

// Схема для групповых сообщений (без receiver_id)
export const sendGroupMessageSchema = Joi.object({
  content: Joi.string().trim().max(VALIDATION_LIMITS.MESSAGE_MAX_LENGTH).allow('').optional(),
  type: Joi.string().valid('text', 'poll').optional(),
  question: Joi.when('type', {
    is: 'poll',
    then: Joi.string().trim().min(1).max(VALIDATION_LIMITS.POLL_QUESTION_MAX_LENGTH).required(),
    otherwise: Joi.optional(),
  }),
  options: Joi.when('type', {
    is: 'poll',
    then: Joi.array().items(Joi.string().trim().max(VALIDATION_LIMITS.POLL_OPTION_MAX_LENGTH)).min(VALIDATION_LIMITS.POLL_MIN_OPTIONS).max(VALIDATION_LIMITS.POLL_MAX_OPTIONS).required(),
    otherwise: Joi.optional(),
  }),
  multiple: Joi.when('type', {
    is: 'poll',
    then: Joi.boolean().optional(),
    otherwise: Joi.optional(),
  }),
  reply_to_id: Joi.number().integer().positive().optional().allow(null),
  is_forwarded: Joi.boolean().optional(),
  forward_from_sender_id: Joi.when('is_forwarded', {
    is: true,
    then: Joi.number().integer().positive().optional(),
    otherwise: Joi.optional(),
  }),
  forward_from_display_name: Joi.when('is_forwarded', {
    is: true,
    then: Joi.string().trim().max(128).optional(),
    otherwise: Joi.optional(),
  }),
}).custom((value, helpers) => {
  // Проверка: должно быть либо content, либо файл, либо опрос
  if (!value.content && !value.type && !helpers.state.ancestors[0]?.files?.length) {
    return helpers.error('any.required', { message: 'content или файл обязательны' });
  }
  return value;
});

// Схемы для опросов
export const votePollSchema = Joi.object({
  option_index: Joi.number().integer().min(0).max(9).required(),
});

export const voteGroupPollSchema = Joi.object({
  option_index: Joi.number().integer().min(0).max(9).optional(),
  option_indices: Joi.array().items(Joi.number().integer().min(0).max(9)).optional(),
}).or('option_index', 'option_indices');

// Схемы для реакций
export const addReactionSchema = Joi.object({
  emoji: Joi.string().valid(...ALLOWED_REACTION_EMOJIS).required(),
});

// Валидация параметров URL
export const validateParams = (schema) => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.params, {
      abortEarly: false,
      stripUnknown: true,
    });

    if (error) {
      const errors = error.details.map((detail) => detail.message);
      return res.status(400).json({ error: errors.join('; ') });
    }

    req.validatedParams = value;
    next();
  };
};

// Схемы для параметров
export const idParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

export const peerIdParamSchema = Joi.object({
  peerId: Joi.number().integer().positive().required(),
});

export const messageIdParamSchema = Joi.object({
  messageId: Joi.number().integer().positive().required(),
});

export const userIdParamSchema = Joi.object({
  userId: Joi.number().integer().positive().required(),
});

export const groupIdAndMessageIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
  messageId: Joi.number().integer().positive().required(),
});

export const groupIdAndPollIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
  pollId: Joi.number().integer().positive().required(),
});

export const readGroupSchema = Joi.object({
  last_message_id: Joi.number().integer().min(0).required(),
});
