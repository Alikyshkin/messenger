/**
 * Константы приложения
 */

// Порты по умолчанию (переопределяются через PORT, PLAYWRIGHT_TEST_PORT, PLAYWRIGHT_CLIENT_PORT)
export const DEFAULT_HTTP_PORT = 3000;

/** Порты для тестов Playwright (используются, если переменные окружения не заданы) */
export const TEST_PORTS = {
  PLAYWRIGHT_API: 48473,
  PLAYWRIGHT_E2E: 38473,
  PLAYWRIGHT_CLIENT: 8765,
};

// Лимиты файлов
export const FILE_LIMITS = {
  MAX_FILE_SIZE: 100 * 1024 * 1024, // 100 MB
  MAX_AVATAR_SIZE: 2 * 1024 * 1024, // 2 MB
  MAX_FILES_PER_MESSAGE: 20,
  MIN_SIZE_TO_COMPRESS: 100 * 1024, // 100 KB
};

// Лимиты валидации
export const VALIDATION_LIMITS = {
  USERNAME_MIN_LENGTH: 3,
  USERNAME_MAX_LENGTH: 50,
  PASSWORD_MIN_LENGTH: 6,
  PASSWORD_MAX_LENGTH: 128,
  DISPLAY_NAME_MAX_LENGTH: 100,
  BIO_MAX_LENGTH: 256,
  MESSAGE_MAX_LENGTH: 10000,
  GROUP_NAME_MAX_LENGTH: 100,
  POLL_QUESTION_MAX_LENGTH: 500,
  POLL_OPTION_MAX_LENGTH: 200,
  POLL_MAX_OPTIONS: 10,
  POLL_MIN_OPTIONS: 2,
};

// Пагинация
export const PAGINATION = {
  DEFAULT_LIMIT: 50,
  MAX_LIMIT: 200,
  MIN_LIMIT: 1,
};

// Разрешённые типы файлов
export const ALLOWED_FILE_TYPES = {
  IMAGES: ['.jpg', '.jpeg', '.png', '.gif', '.webp'],
  VIDEOS: ['.mp4', '.webm', '.mov'],
  AUDIO: ['.mp3', '.wav', '.ogg', '.webm'],
  DOCUMENTS: ['.pdf', '.doc', '.docx', '.txt', '.md'],
  BLOCKED: ['.exe', '.bat', '.cmd', '.sh', '.dll', '.so', '.dylib'],
};

// Разрешённые эмодзи для реакций
export const ALLOWED_REACTION_EMOJIS = ['👍', '👎', '❤️', '🔥', '😂', '😮', '😢'];

// JWT настройки
export const JWT_CONFIG = {
  EXPIRES_IN: '7d',
  DEFAULT_SECRET: 'messenger-dev-secret-change-in-production',
};

// База данных
export const DB_CONFIG = {
  DEFAULT_PATH: 'messenger.db',
  BACKUP_RETENTION_DAYS: 30,
};

// Время жизни токенов
export const TOKEN_EXPIRY = {
  PASSWORD_RESET_HOURS: 1,
  JWT_DAYS: 7,
};

// Поиск
export const SEARCH_CONFIG = {
  MIN_QUERY_LENGTH: 2,
  MAX_RESULTS: 20,
};

// WebSocket
export const WS_CONFIG = {
  PATH: '/ws',
  UNAUTHORIZED_CODE: 4001,
};

// HTTP статусы
export const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  NO_CONTENT: 204,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  TOO_MANY_REQUESTS: 429,
  INTERNAL_SERVER_ERROR: 500,
  SERVICE_UNAVAILABLE: 503,
};

// Роли в группах
export const GROUP_ROLES = {
  ADMIN: 'admin',
  MEMBER: 'member',
};

// Типы сообщений
export const MESSAGE_TYPES = {
  TEXT: 'text',
  POLL: 'poll',
};

// Типы вложений
export const ATTACHMENT_KINDS = {
  FILE: 'file',
  VOICE: 'voice',
  VIDEO_NOTE: 'video_note',
};

// Статусы заявок в друзья
export const FRIEND_REQUEST_STATUS = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
};
