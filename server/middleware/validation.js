import Joi from 'joi';

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
  username: Joi.string().trim().min(3).max(50).required()
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
      'string.min': 'Имя пользователя минимум 3 символа',
      'string.max': 'Имя пользователя максимум 50 символов',
    }),
  password: Joi.string().min(6).max(128).required()
    .messages({
      'string.min': 'Пароль минимум 6 символов',
      'string.max': 'Пароль максимум 128 символов',
    }),
  displayName: Joi.string().trim().max(100).allow('').optional(),
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
  newPassword: Joi.string().min(6).max(128).required()
    .messages({
      'string.min': 'Пароль минимум 6 символов',
      'string.max': 'Пароль максимум 128 символов',
    }),
});

export const changePasswordSchema = Joi.object({
  currentPassword: Joi.string().required(),
  newPassword: Joi.string().min(6).max(128).required()
    .messages({
      'string.min': 'Пароль минимум 6 символов',
      'string.max': 'Пароль максимум 128 символов',
    }),
});

// Схемы для пользователей
export const updateUserSchema = Joi.object({
  display_name: Joi.string().trim().max(100).allow('').optional(),
  username: Joi.string().trim().min(3).max(50).optional()
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
    }),
  bio: Joi.string().trim().max(256).allow('').optional(),
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
  content: Joi.string().trim().max(10000).allow('').optional(),
  type: Joi.string().valid('text', 'poll').optional(),
  question: Joi.when('type', {
    is: 'poll',
    then: Joi.string().trim().min(1).max(500).required(),
    otherwise: Joi.optional(),
  }),
  options: Joi.when('type', {
    is: 'poll',
    then: Joi.array().items(Joi.string().trim().max(200)).min(2).max(10).required(),
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
  username: Joi.string().trim().min(3).max(50).required(),
});

// Схемы для групп
export const createGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(100).required()
    .messages({
      'string.min': 'Название группы обязательно',
      'string.max': 'Название группы максимум 100 символов',
    }),
  member_ids: Joi.array().items(Joi.number().integer().positive()).optional(),
});

export const updateGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(100).optional(),
});

export const addGroupMemberSchema = Joi.object({
  username: Joi.string().trim().min(3).max(50).required(),
});

// Схема для групповых сообщений (без receiver_id)
export const sendGroupMessageSchema = Joi.object({
  content: Joi.string().trim().max(10000).allow('').optional(),
  type: Joi.string().valid('text', 'poll').optional(),
  question: Joi.when('type', {
    is: 'poll',
    then: Joi.string().trim().min(1).max(500).required(),
    otherwise: Joi.optional(),
  }),
  options: Joi.when('type', {
    is: 'poll',
    then: Joi.array().items(Joi.string().trim().max(200)).min(2).max(10).required(),
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
  emoji: Joi.string().valid('👍', '👎', '❤️', '🔥', '😂', '😮', '😢').required(),
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
