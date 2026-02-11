// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Утилита для проверки обновлений и очистки кеша в Flutter Web
class AppUpdateWeb {
  /// Проверяет наличие обновлений и перезагружает страницу с очисткой кеша
  /// Вызывается при выходе из звонка для синхронизации интерфейса и обновлений
  static Future<void> checkAndReloadIfNeeded() async {
    if (!kIsWeb) {
      return;
    }

    try {
      // Очищаем кеш перед перезагрузкой
      await clearCache();

      // Небольшая задержка для завершения очистки кеша
      await Future.delayed(const Duration(milliseconds: 100));

      // Перезагружаем страницу с очисткой кеша
      // Добавляем параметр для принудительной перезагрузки без кеша
      final url = Uri.parse(html.window.location.href);
      final newUrl = url.replace(
        queryParameters: {
          ...url.queryParameters,
          '_reload': DateTime.now().millisecondsSinceEpoch.toString(),
          '_nocache': '1',
        },
      );

      // Перезагружаем страницу
      html.window.location.href = newUrl.toString();
    } catch (_) {
      // Если произошла ошибка, просто перезагружаем страницу
      html.window.location.reload();
    }
  }

  /// Принудительно перезагружает страницу с очисткой кеша
  static void forceReloadWithCacheClear() {
    if (!kIsWeb) {
      return;
    }
    checkAndReloadIfNeeded();
  }

  /// Очищает кеш браузера для текущего домена
  static Future<void> clearCache() async {
    if (!kIsWeb) {
      return;
    }

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

      // Очищаем кеш Service Worker если доступен
      if (html.window.navigator.serviceWorker != null) {
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
    } catch (_) {
      // Игнорируем ошибки очистки кеша
    }
  }
}
