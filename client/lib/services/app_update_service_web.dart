// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web-специфичная реализация для обновления приложения
class AppUpdateServiceWeb {
  /// Перезагружает страницу с очисткой кеша
  static Future<void> reloadWithCacheClear() async {
    try {
      // Очищаем кеш через Cache API если доступен
      if (html.window.caches != null) {
        final cacheNames = await html.window.caches!.keys();
        for (final cacheName in cacheNames) {
          try {
            await html.window.caches!.delete(cacheName);
          } catch (_) {
            // Игнорируем ошибки удаления отдельных кешей
          }
        }
      }

      // Перезагружаем страницу
      html.window.location.reload();
    } catch (_) {
      // Если произошла ошибка, просто перезагружаем
      html.window.location.reload();
    }
  }
}
