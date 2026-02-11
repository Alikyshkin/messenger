import Joi from 'joi';
import { PAGINATION } from '../config/constants.js';

/**
 * Валидация параметров пагинации
 */
export const paginationSchema = Joi.object({
  limit: Joi.number().integer().min(PAGINATION.MIN_LIMIT).max(PAGINATION.MAX_LIMIT).default(PAGINATION.DEFAULT_LIMIT),
  offset: Joi.number().integer().min(0).default(0),
  before: Joi.number().integer().positive().optional(),
  after: Joi.number().integer().positive().optional(),
});

/**
 * Middleware для валидации параметров пагинации
 */
export function validatePagination(req, res, next) {
  const { error, value } = paginationSchema.validate(req.query, {
    abortEarly: false,
    stripUnknown: true,
  });

  if (error) {
    return res.status(400).json({ error: error.details.map(d => d.message).join('; ') });
  }

  req.pagination = value;
  next();
}

/**
 * Создаёт метаданные пагинации для ответа
 */
export function createPaginationMeta(total, limit, offset) {
  return {
    total,
    limit,
    offset,
    hasMore: offset + limit < total,
    page: Math.floor(offset / limit) + 1,
    totalPages: Math.ceil(total / limit),
  };
}
