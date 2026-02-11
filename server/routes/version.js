import { Router } from 'express';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const router = Router();
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * GET /version
 * Возвращает версию клиентского приложения
 */
router.get('/', (req, res) => {
  try {
    // Читаем версию из package.json клиента или используем версию из env
    let clientVersion = process.env.CLIENT_VERSION || '1.0.0';
    
    try {
      // Пытаемся прочитать версию из pubspec.yaml клиента
      const pubspecPath = join(__dirname, '../../client/pubspec.yaml');
      const pubspecContent = readFileSync(pubspecPath, 'utf-8');
      const versionMatch = pubspecContent.match(/^version:\s*(.+)$/m);
      if (versionMatch) {
        // Извлекаем только версию без build number (1.0.0+1 -> 1.0.0)
        clientVersion = versionMatch[1].split('+')[0].trim();
      }
    } catch (_) {
      // Если не удалось прочитать pubspec.yaml, используем значение по умолчанию
    }
    
    res.json({
      version: clientVersion,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({
      error: 'Не удалось получить версию',
      version: '1.0.0', // Fallback версия
    });
  }
});

export default router;
