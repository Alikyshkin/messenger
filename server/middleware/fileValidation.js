import { fileTypeFromBuffer } from 'file-type';
import fs from 'fs';

// Разрешённые MIME-типы для разных категорий файлов
const ALLOWED_IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
];

const ALLOWED_VIDEO_TYPES = [
  'video/mp4',
  'video/webm',
  'video/quicktime',
];

const ALLOWED_AUDIO_TYPES = [
  'audio/mpeg',
  'audio/mp3',
  'audio/wav',
  'audio/ogg',
  'audio/webm',
];

const ALLOWED_DOCUMENT_TYPES = [
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
  'text/markdown',
];

// Все разрешённые типы
const ALLOWED_TYPES = [
  ...ALLOWED_IMAGE_TYPES,
  ...ALLOWED_VIDEO_TYPES,
  ...ALLOWED_AUDIO_TYPES,
  ...ALLOWED_DOCUMENT_TYPES,
];

/**
 * Проверяет MIME-тип файла по его содержимому (magic bytes)
 * @param {string} filePath - путь к файлу
 * @returns {Promise<{valid: boolean, mime?: string, error?: string}>}
 */
export async function validateFileMimeType(filePath) {
  try {
    const buffer = fs.readFileSync(filePath);
    const fileType = await fileTypeFromBuffer(buffer);
    
    if (!fileType) {
      // Если file-type не определил тип, проверяем по расширению
      const ext = filePath.toLowerCase().split('.').pop();
      const extensionMap = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'md': 'text/markdown',
      };
      
      const mime = extensionMap[ext];
      if (!mime || !ALLOWED_TYPES.includes(mime)) {
        return { valid: false, error: 'Тип файла не разрешён или не определён' };
      }
      return { valid: true, mime };
    }
    
    if (!ALLOWED_TYPES.includes(fileType.mime)) {
      return { valid: false, error: `Тип файла ${fileType.mime} не разрешён` };
    }
    
    return { valid: true, mime: fileType.mime };
  } catch (error) {
    return { valid: false, error: `Ошибка проверки файла: ${error.message}` };
  }
}

/**
 * Проверяет размер файла
 * @param {string} filePath - путь к файлу
 * @param {number} maxSizeBytes - максимальный размер в байтах
 * @returns {Promise<{valid: boolean, size?: number, error?: string}>}
 */
export async function validateFileSize(filePath, maxSizeBytes = 100 * 1024 * 1024) {
  try {
    const stats = fs.statSync(filePath);
    if (stats.size > maxSizeBytes) {
      return { 
        valid: false, 
        error: `Файл слишком большой (${Math.round(stats.size / 1024 / 1024)}MB, максимум ${Math.round(maxSizeBytes / 1024 / 1024)}MB)` 
      };
    }
    return { valid: true, size: stats.size };
  } catch (error) {
    return { valid: false, error: `Ошибка проверки размера: ${error.message}` };
  }
}

/**
 * Проверяет файл на наличие потенциально опасного содержимого
 * @param {string} filePath - путь к файлу
 * @returns {Promise<{valid: boolean, error?: string}>}
 */
export async function scanFileForThreats(filePath) {
  try {
    const buffer = fs.readFileSync(filePath);
    
    // Проверка на исполняемые файлы (PE, ELF, Mach-O)
    const peSignature = buffer.slice(0, 2);
    const elfSignature = buffer.slice(0, 4);
    const machoSignature = buffer.slice(0, 4);
    
    // PE (Windows executable)
    if (peSignature[0] === 0x4D && peSignature[1] === 0x5A) {
      return { valid: false, error: 'Обнаружен исполняемый файл (PE)' };
    }
    
    // ELF (Linux executable)
    if (elfSignature[0] === 0x7F && 
        elfSignature[1] === 0x45 && 
        elfSignature[2] === 0x4C && 
        elfSignature[3] === 0x46) {
      return { valid: false, error: 'Обнаружен исполняемый файл (ELF)' };
    }
    
    // Mach-O (macOS executable)
    if (machoSignature[0] === 0xFE && 
        machoSignature[1] === 0xED && 
        machoSignature[2] === 0xFA && 
        machoSignature[3] === 0xCE) {
      return { valid: false, error: 'Обнаружен исполняемый файл (Mach-O)' };
    }
    
    // Проверка на скрипты (проверяем первые несколько байт на наличие shebang)
    const textStart = buffer.slice(0, 100).toString('utf8', 0, 100);
    if (textStart.startsWith('#!')) {
      const scriptExtensions = ['sh', 'bash', 'zsh', 'python', 'perl', 'ruby', 'php', 'node'];
      const ext = filePath.toLowerCase().split('.').pop();
      if (scriptExtensions.includes(ext)) {
        return { valid: false, error: 'Обнаружен скрипт' };
      }
    }
    
    return { valid: true };
  } catch (error) {
    return { valid: false, error: `Ошибка сканирования: ${error.message}` };
  }
}

/**
 * Комплексная проверка файла
 * @param {string} filePath - путь к файлу
 * @param {number} maxSizeBytes - максимальный размер в байтах
 * @returns {Promise<{valid: boolean, mime?: string, size?: number, error?: string}>}
 */
export async function validateFile(filePath, maxSizeBytes = 100 * 1024 * 1024) {
  // Проверка размера
  const sizeCheck = await validateFileSize(filePath, maxSizeBytes);
  if (!sizeCheck.valid) {
    return sizeCheck;
  }
  
  // Проверка MIME-типа
  const mimeCheck = await validateFileMimeType(filePath);
  if (!mimeCheck.valid) {
    return mimeCheck;
  }
  
  // Сканирование на угрозы
  const threatCheck = await scanFileForThreats(filePath);
  if (!threatCheck.valid) {
    return threatCheck;
  }
  
  return {
    valid: true,
    mime: mimeCheck.mime,
    size: sizeCheck.size,
  };
}
