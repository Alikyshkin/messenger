import { JSDOM } from 'jsdom';
import DOMPurify from 'dompurify';

const window = new JSDOM('').window;
const purify = DOMPurify(window);

/**
 * Санитизирует HTML-контент, удаляя потенциально опасные теги и атрибуты
 * Разрешает только безопасные теги для форматирования текста
 */
export function sanitizeHtml(html) {
  if (typeof html !== 'string') return '';
  
  return purify.sanitize(html, {
    ALLOWED_TAGS: ['b', 'i', 'u', 'em', 'strong', 'br', 'p', 'span'],
    ALLOWED_ATTR: [],
    KEEP_CONTENT: true,
  });
}

/**
 * Экранирует HTML-символы для безопасного отображения
 */
export function escapeHtml(text) {
  if (typeof text !== 'string') return '';
  
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;',
  };
  
  return text.replace(/[&<>"']/g, (m) => map[m]);
}

/**
 * Санитизирует обычный текст, удаляя потенциально опасные символы
 */
export function sanitizeText(text) {
  if (typeof text !== 'string') return '';
  
  // Удаляем управляющие символы, кроме переносов строк и табуляции
  return text
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim();
}
