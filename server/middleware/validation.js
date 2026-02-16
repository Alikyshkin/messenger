import Joi from 'joi';
import zxcvbn from 'zxcvbn';
import { VALIDATION_LIMITS, ALLOWED_REACTION_EMOJIS } from '../config/constants.js';
import { log } from '../utils/logger.js';

// Middleware для валидации запросов
export const validate = (schema) => {
  return (req, res, next) => {
    log.info({ path: req.path, method: req.method }, 'Validation middleware - start');
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,
      stripUnknown: true,
      messages: {
        'any.required': '{{#label}} обязательно для заполнения',
        'string.empty': '{{#label}} не может быть пустым',
        'string.min': '{{#label}} должно быть минимум {{#limit}} символов',
        'string.max': '{{#label}} должно быть максимум {{#limit}} символов',
        'number.base': '{{#label}} должно быть числом',
        'number.positive': '{{#label}} должно быть положительным числом',
        'number.integer': '{{#label}} должно быть целым числом',
        'boolean.base': '{{#label}} должно быть true или false',
        'array.base': '{{#label}} должно быть списком',
        'array.min': '{{#label}} должно содержать минимум {{#limit}} элементов',
        'array.max': '{{#label}} должно содержать максимум {{#limit}} элементов',
        'any.only': '{{#label}} должно быть одним из: {{#valids}}',
        'string.email': '{{#label}} должен быть корректным email',
        'string.pattern.base': '{{#label}} имеет неверный формат',
      },
    });

    if (error) {
      log.warn({ 
        path: req.path, 
        method: req.method, 
        errors: error.details,
        body: req.body 
      }, 'Validation failed');
      const errors = error.details.map((detail) => {
        // Переводим стандартные сообщения Joi на русский
        let message = detail.message;
        message = message.replace(/\"([^\"]+)\"/g, '$1'); // Убираем кавычки
        message = message.replace(/must be/, 'должно быть');
        message = message.replace(/is required/, 'обязательно для заполнения');
        message = message.replace(/must be one of/, 'должно быть одним из');
        message = message.replace(/length must be/, 'длина должна быть');
        message = message.replace(/at least/, 'минимум');
        message = message.replace(/at most/, 'максимум');
        message = message.replace(/characters long/, 'символов');
        message = message.replace(/must be a number/, 'должно быть числом');
        message = message.replace(/must be a string/, 'должно быть текстом');
        message = message.replace(/must be a boolean/, 'должно быть true или false');
        message = message.replace(/must be an array/, 'должно быть списком');
        message = message.replace(/must be a valid email/, 'должен быть корректным email');
        message = message.replace(/must be a valid date/, 'должна быть корректной датой');
        message = message.replace(/must be greater than/, 'должно быть больше');
        message = message.replace(/must be less than/, 'должно быть меньше');
        message = message.replace(/must contain/, 'должно содержать');
        message = message.replace(/must match/, 'должно соответствовать');
        return message;
      });
      return res.status(400).json({ error: errors.join('; ') });
    }

    req.validated = value;
    log.info({ path: req.path, method: req.method }, 'Validation middleware - success, calling next()');
    next();
  };
};

// Валидация силы пароля
const passwordStrength = (value, helpers) => {
  if (!value) return value;
  
  const result = zxcvbn(value);
  
  // Минимальный score: 2 (weak) или выше
  if (result.score < 2) {
    const feedback = result.feedback.suggestions.length > 0
      ? result.feedback.suggestions.join(' ')
      : 'Пароль слишком слабый. Используйте комбинацию букв, цифр и специальных символов.';
    
    return helpers.error('password.weak', { message: feedback });
  }
  
  return value;
};

// Схемы валидации для аутентификации
export const registerSchema = Joi.object({
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required()
    .label('Имя пользователя')
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'any.required': 'Имя пользователя обязательно',
      'string.empty': 'Имя пользователя не может быть пустым',
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
      'string.min': `Имя пользователя минимум ${VALIDATION_LIMITS.USERNAME_MIN_LENGTH} символа`,
      'string.max': `Имя пользователя максимум ${VALIDATION_LIMITS.USERNAME_MAX_LENGTH} символов`,
    }),
  password: Joi.string()
    .label('Пароль')
    .min(8) // Минимум 8 символов
    .max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH)
    .required()
    .custom(passwordStrength, 'password strength validation')
    .messages({
      'any.required': 'Пароль обязателен',
      'string.empty': 'Пароль не может быть пустым',
      'password.weak': '{{#message}}',
      'string.min': 'Пароль должен содержать минимум 8 символов',
      'string.max': `Пароль не должен превышать ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
  displayName: Joi.string().trim().max(VALIDATION_LIMITS.DISPLAY_NAME_MAX_LENGTH).allow('').optional()
    .label('Отображаемое имя'),
  email: Joi.string().email().trim().lowercase().max(255).optional().allow('', null)
    .label('Email')
    .messages({
      'string.email': 'Email должен быть корректным',
    }),
});

export const loginSchema = Joi.object({
  username: Joi.string().trim().required()
    .label('Имя пользователя')
    .messages({
      'any.required': 'Имя пользователя обязательно',
      'string.empty': 'Имя пользователя не может быть пустым',
    }),
  password: Joi.string().required()
    .label('Пароль')
    .messages({
      'any.required': 'Пароль обязателен',
      'string.empty': 'Пароль не может быть пустым',
    }),
});

export const forgotPasswordSchema = Joi.object({
  email: Joi.string().email().trim().lowercase().required()
    .label('Email')
    .messages({
      'any.required': 'Email обязателен',
      'string.empty': 'Email не может быть пустым',
      'string.email': 'Некорректный формат email',
    }),
});

export const resetPasswordSchema = Joi.object({
  token: Joi.string().required()
    .label('Токен')
    .messages({
      'any.required': 'Токен обязателен',
      'string.empty': 'Токен не может быть пустым',
    }),
  newPassword: Joi.string()
    .label('Новый пароль')
    .min(8)
    .max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH)
    .required()
    .custom(passwordStrength, 'password strength validation')
    .messages({
      'any.required': 'Новый пароль обязателен',
      'string.empty': 'Новый пароль не может быть пустым',
      'password.weak': '{{#message}}',
      'string.min': 'Пароль должен содержать минимум 8 символов',
      'string.max': `Пароль не должен превышать ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
});

// OAuth схемы
export const googleAuthSchema = Joi.object({
  idToken: Joi.string().required().label('Google ID Token'),
});

export const vkAuthSchema = Joi.object({
  accessToken: Joi.string().required().label('VK Access Token'),
  userId: Joi.string().required().label('VK User ID'),
});

export const telegramAuthSchema = Joi.object({
  id: Joi.number().integer().positive().required().label('Telegram ID'),
  first_name: Joi.string().allow('').optional(),
  last_name: Joi.string().allow('').optional(),
  username: Joi.string().allow('').optional(),
  photo_url: Joi.string().uri().allow('').optional(),
  auth_date: Joi.number().integer().required().label('Auth date'),
  hash: Joi.string().required().label('Hash'),
});

export const phoneSendCodeSchema = Joi.object({
  phone: Joi.string().pattern(/^\+?\d{10,15}$/).required().label('Телефон')
    .messages({ 'string.pattern.base': 'Некорректный номер телефона' }),
});

export const phoneVerifySchema = Joi.object({
  phone: Joi.string().pattern(/^\+?\d{10,15}$/).required().label('Телефон')
    .messages({ 'string.pattern.base': 'Некорректный номер телефона' }),
  code: Joi.string().length(6).pattern(/^\d+$/).required().label('Код')
    .messages({ 'string.pattern.base': 'Код должен содержать 6 цифр' }),
});

export const changePasswordSchema = Joi.object({
  currentPassword: Joi.string().required()
    .label('Текущий пароль')
    .messages({
      'any.required': 'Текущий пароль обязателен',
      'string.empty': 'Текущий пароль не может быть пустым',
    }),
  newPassword: Joi.string()
    .label('Новый пароль')
    .min(8)
    .max(VALIDATION_LIMITS.PASSWORD_MAX_LENGTH)
    .required()
    .custom(passwordStrength, 'password strength validation')
    .messages({
      'any.required': 'Новый пароль обязателен',
      'string.empty': 'Новый пароль не может быть пустым',
      'password.weak': '{{#message}}',
      'string.min': 'Пароль должен содержать минимум 8 символов',
      'string.max': `Пароль не должен превышать ${VALIDATION_LIMITS.PASSWORD_MAX_LENGTH} символов`,
    }),
});

// Схемы для пользователей
export const updateUserSchema = Joi.object({
  display_name: Joi.string().trim().max(VALIDATION_LIMITS.DISPLAY_NAME_MAX_LENGTH).allow('').optional()
    .label('Отображаемое имя'),
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).optional()
    .label('Имя пользователя')
    .pattern(/^[a-z0-9_]+$/)
    .messages({
      'string.pattern.base': 'Имя пользователя может содержать только строчные буквы, цифры и подчёркивание',
      'string.min': `Имя пользователя минимум ${VALIDATION_LIMITS.USERNAME_MIN_LENGTH} символа`,
      'string.max': `Имя пользователя максимум ${VALIDATION_LIMITS.USERNAME_MAX_LENGTH} символов`,
    }),
  bio: Joi.string().trim().max(VALIDATION_LIMITS.BIO_MAX_LENGTH).allow('').optional()
    .label('О себе'),
  email: Joi.string().email().trim().lowercase().max(255).allow('', null).optional()
    .label('Email')
    .messages({
      'string.email': 'Email должен быть корректным',
    }),
  birthday: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional().allow('', null)
    .label('День рождения')
    .messages({
      'string.pattern.base': 'День рождения в формате ГГГГ-ММ-ДД',
    }),
  phone: Joi.string().pattern(/^\d{10,15}$/).optional().allow('', null)
    .label('Телефон')
    .messages({
      'string.pattern.base': 'Некорректный номер телефона',
    }),
  public_key: Joi.string().max(500).allow('', null).optional()
    .label('Публичный ключ'),
});

export const updatePrivacySchema = Joi.object({
  who_can_see_status: Joi.string().valid('all', 'contacts', 'nobody').optional(),
  who_can_message: Joi.string().valid('all', 'contacts', 'nobody').optional(),
  who_can_call: Joi.string().valid('all', 'contacts', 'nobody').optional(),
});

export const addHideFromSchema = Joi.object({
  user_id: Joi.number().integer().positive().required().label('ID пользователя'),
});

// Схемы для сообщений
export const sendMessageSchema = Joi.object({
  receiver_id: Joi.number().integer().positive().required()
    .label('ID получателя')
    .messages({
      'any.required': 'ID получателя обязателен',
      'number.base': 'ID получателя должно быть числом',
      'number.positive': 'ID получателя должно быть положительным числом',
      'number.integer': 'ID получателя должно быть целым числом',
    }),
  content: Joi.string().trim().max(VALIDATION_LIMITS.MESSAGE_MAX_LENGTH).allow('').optional(),
  type: Joi.string().valid('text', 'poll', 'missed_call').optional(),
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
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required()
    .label('Имя пользователя')
    .messages({
      'any.required': 'Имя пользователя обязательно',
      'string.empty': 'Имя пользователя не может быть пустым',
      'string.min': `Имя пользователя минимум ${VALIDATION_LIMITS.USERNAME_MIN_LENGTH} символа`,
      'string.max': `Имя пользователя максимум ${VALIDATION_LIMITS.USERNAME_MAX_LENGTH} символов`,
    }),
});

// Схемы для групп
export const createGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH).required()
    .label('Название группы')
    .messages({
      'any.required': 'Название группы обязательно',
      'string.empty': 'Название группы не может быть пустым',
      'string.min': 'Название группы обязательно',
      'string.max': `Название группы максимум ${VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH} символов`,
    }),
  member_ids: Joi.array().items(Joi.number().integer().positive()).optional()
    .label('ID участников'),
});

export const updateGroupSchema = Joi.object({
  name: Joi.string().trim().min(1).max(VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH).optional()
    .label('Название группы')
    .messages({
      'string.min': 'Название группы не может быть пустым',
      'string.max': `Название группы максимум ${VALIDATION_LIMITS.GROUP_NAME_MAX_LENGTH} символов`,
    }),
});

export const addGroupMemberSchema = Joi.object({
  username: Joi.string().trim().min(VALIDATION_LIMITS.USERNAME_MIN_LENGTH).max(VALIDATION_LIMITS.USERNAME_MAX_LENGTH).required()
    .label('Имя пользователя')
    .messages({
      'any.required': 'Имя пользователя обязательно',
      'string.empty': 'Имя пользователя не может быть пустым',
      'string.min': `Имя пользователя минимум ${VALIDATION_LIMITS.USERNAME_MIN_LENGTH} символа`,
      'string.max': `Имя пользователя максимум ${VALIDATION_LIMITS.USERNAME_MAX_LENGTH} символов`,
    }),
});

// Схема для групповых сообщений (без receiver_id)
export const sendGroupMessageSchema = Joi.object({
  content: Joi.string().trim().max(VALIDATION_LIMITS.MESSAGE_MAX_LENGTH).allow('').optional()
    .label('Содержание сообщения'),
  type: Joi.string().valid('text', 'poll').optional()
    .label('Тип сообщения'),
  question: Joi.when('type', {
    is: 'poll',
    then: Joi.string().trim().min(1).max(VALIDATION_LIMITS.POLL_QUESTION_MAX_LENGTH).required()
      .label('Вопрос опроса')
      .messages({
        'any.required': 'Вопрос опроса обязателен',
        'string.min': 'Вопрос опроса не может быть пустым',
        'string.max': `Вопрос опроса максимум ${VALIDATION_LIMITS.POLL_QUESTION_MAX_LENGTH} символов`,
      }),
    otherwise: Joi.optional(),
  }),
  options: Joi.when('type', {
    is: 'poll',
    then: Joi.array().items(Joi.string().trim().max(VALIDATION_LIMITS.POLL_OPTION_MAX_LENGTH)).min(VALIDATION_LIMITS.POLL_MIN_OPTIONS).max(VALIDATION_LIMITS.POLL_MAX_OPTIONS).required()
      .label('Варианты ответа')
      .messages({
        'any.required': 'Варианты ответа обязательны',
        'array.min': `Минимум ${VALIDATION_LIMITS.POLL_MIN_OPTIONS} варианта ответа`,
        'array.max': `Максимум ${VALIDATION_LIMITS.POLL_MAX_OPTIONS} вариантов ответа`,
      }),
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
  option_index: Joi.number().integer().min(0).max(9).required()
    .messages({
      'any.required': 'Индекс варианта ответа обязателен',
      'number.base': 'Индекс варианта должен быть числом',
      'number.min': 'Индекс варианта должен быть от 0 до 9',
      'number.max': 'Индекс варианта должен быть от 0 до 9',
    }),
});

export const voteGroupPollSchema = Joi.object({
  option_index: Joi.number().integer().min(0).max(9).optional()
    .label('Индекс варианта ответа'),
  option_indices: Joi.array().items(Joi.number().integer().min(0).max(9)).optional()
    .label('Индексы вариантов ответа'),
}).or('option_index', 'option_indices')
  .messages({
    'object.missing': 'Необходимо указать option_index или option_indices',
  });

// Схемы для реакций
export const addReactionSchema = Joi.object({
  emoji: Joi.string().valid(...ALLOWED_REACTION_EMOJIS).required()
    .messages({
      'any.required': 'Эмодзи обязательно',
      'any.only': 'Недопустимый эмодзи',
    }),
});

// Валидация параметров URL
export const validateParams = (schema) => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.params, {
      abortEarly: false,
      stripUnknown: true,
      messages: {
        'any.required': '{{#label}} обязательно',
        'number.base': '{{#label}} должно быть числом',
        'number.positive': '{{#label}} должно быть положительным числом',
        'number.integer': '{{#label}} должно быть целым числом',
      },
    });

    if (error) {
      const errors = error.details.map((detail) => {
        let message = detail.message;
        message = message.replace(/\"([^\"]+)\"/g, '$1');
        message = message.replace(/must be/, 'должно быть');
        message = message.replace(/is required/, 'обязательно');
        return message;
      });
      return res.status(400).json({ error: errors.join('; ') });
    }

    req.validatedParams = value;
    next();
  };
};

// Схемы для параметров
export const idParamSchema = Joi.object({
  id: Joi.number().integer().positive().required()
    .label('ID')
    .messages({
      'any.required': 'ID обязателен',
      'number.base': 'ID должно быть числом',
      'number.positive': 'ID должно быть положительным числом',
    }),
});

export const peerIdParamSchema = Joi.object({
  peerId: Joi.number().integer().positive().required()
    .label('ID собеседника')
    .messages({
      'any.required': 'ID собеседника обязательно',
      'number.base': 'ID собеседника должно быть числом',
      'number.positive': 'ID собеседника должно быть положительным числом',
    }),
});

export const editMessageSchema = Joi.object({
  content: Joi.string().trim().min(1).max(VALIDATION_LIMITS.MESSAGE_MAX_LENGTH).required()
    .label('Текст сообщения')
    .messages({
      'any.required': 'Текст сообщения обязателен',
      'string.empty': 'Текст сообщения не может быть пустым',
      'string.max': `Текст сообщения максимум ${VALIDATION_LIMITS.MESSAGE_MAX_LENGTH} символов`,
    }),
});

export const messageIdParamSchema = Joi.object({
  messageId: Joi.number().integer().positive().required()
    .label('ID сообщения')
    .messages({
      'any.required': 'ID сообщения обязательно',
      'number.base': 'ID сообщения должно быть числом',
      'number.positive': 'ID сообщения должно быть положительным числом',
    }),
});

export const userIdParamSchema = Joi.object({
  userId: Joi.number().integer().positive().required()
    .label('ID пользователя')
    .messages({
      'any.required': 'ID пользователя обязательно',
      'number.base': 'ID пользователя должно быть числом',
      'number.positive': 'ID пользователя должно быть положительным числом',
    }),
});

export const groupIdAndMessageIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required()
    .label('ID группы')
    .messages({
      'any.required': 'ID группы обязательно',
      'number.base': 'ID группы должно быть числом',
      'number.positive': 'ID группы должно быть положительным числом',
    }),
  messageId: Joi.number().integer().positive().required()
    .label('ID сообщения')
    .messages({
      'any.required': 'ID сообщения обязательно',
      'number.base': 'ID сообщения должно быть числом',
      'number.positive': 'ID сообщения должно быть положительным числом',
    }),
});

export const groupIdAndPollIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required()
    .label('ID группы')
    .messages({
      'any.required': 'ID группы обязательно',
      'number.base': 'ID группы должно быть числом',
      'number.positive': 'ID группы должно быть положительным числом',
    }),
  pollId: Joi.number().integer().positive().required()
    .label('ID опроса')
    .messages({
      'any.required': 'ID опроса обязательно',
      'number.base': 'ID опроса должно быть числом',
      'number.positive': 'ID опроса должно быть положительным числом',
    }),
});

export const readGroupSchema = Joi.object({
  last_message_id: Joi.number().integer().min(0).required()
    .label('ID последнего сообщения')
    .messages({
      'any.required': 'ID последнего сообщения обязательно',
      'number.base': 'ID последнего сообщения должно быть числом',
      'number.min': 'ID последнего сообщения должно быть неотрицательным числом',
    }),
});
