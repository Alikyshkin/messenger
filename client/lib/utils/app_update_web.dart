// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Утилита для проверки обновлений и очистки кеша в Flutter Web
class AppUpdateWeb {
  /// Проверяет наличие обновлений и при необходимости перезагружает страницу с очисткой кеша
  static Future<void> checkAndReloadIfNeeded() async {
    if (!kIsWeb) return;
    
    try {
      // Проверяем наличие Service Worker для обновлений
      if (html.window.navigator.serviceWorker != null) {
        // Регистрируем Service Worker если он еще не зарегистрирован
        try {
          final registration = await html.window.navigator.serviceWorker?.ready;
          if (registration != null) {
            // Проверяем наличие обновлений через Service Worker
            await registration.update();
          }
        } catch (_) {
          // Игнорируем ошибки Service Worker
        }
      }
      
      // Проверяем версию приложения через запрос к серверу
      await _checkAppVersion();
    } catch (_) {
      // Игнорируем ошибки проверки обновлений
    }
  }
  
  /// Проверяет версию приложения и перезагружает если есть обновления
  static Future<void> _checkAppVersion() async {
    try {
      // Запрашиваем версию приложения с сервера
      final response = await html.HttpRequest.getString(
        '${html.window.location.origin}/version.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      
      // Если версия изменилась, перезагружаем страницу с очисткой кеша
      // Для простоты всегда перезагружаем при выходе из звонка для синхронизации
      await _reloadWithCacheClear();
    } catch (_) {
      // Если не удалось проверить версию, все равно перезагружаем для синхронизации
      await _reloadWithCacheClear();
    }
  }
  
  /// Перезагружает страницу с очисткой кеша
  static Future<void> _reloadWithCacheClear() async {
    // Добавляем параметр для очистки кеша
    final url = html.Uri.parse(html.window.location.href);
    final newUrl = url.replace(queryParameters: {
      ...url.queryParameters,
      '_reload': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    
    // Перезагружаем страницу с очисткой кеша
    html.window.location.reload();
  }
  
  /// Принудительно перезагружает страницу с очисткой кеша
  static void forceReloadWithCacheClear() {
    if (!kIsWeb) return;
    html.window.location.reload();
  }
  
  /// Очищает кеш браузера для текущего домена
  static Future<void> clearCache() async {
    if (!kIsWeb) return;
    
    try {
      // Очищаем кеш через Cache API если доступен
      if (html.window.navigator.serviceWorker != null) {
        final registration = await html.window.navigator.serviceWorker?.ready;
        if (registration != null) {
          // Очищаем кеш Service Worker
          final cacheNames = await html.window.caches?.keys();
          if (cacheNames != null) {
            for (final cacheName in cacheNames) {
              await html.window.caches?.delete(cacheName);
            }
          }
        }
      }
    } catch (_) {
      // Игнорируем ошибки очистки кеша
    }
  }
}
