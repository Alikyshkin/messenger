import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_update_service.dart';
import '../services/chat_list_refresh_service.dart';
import '../utils/user_action_logger.dart';

/// NavigatorObserver для проверки обновлений при навигации
/// Проверяет обновления только при переходе на главный экран, чтобы не перегружать сервер
class NavigationUpdateObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    logUserAction('nav_push', {
      'route': route.settings.name ?? route.settings.toString(),
    });
    _checkForUpdatesIfHome(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    logUserAction('nav_pop', {
      'route': route.settings.name ?? route.settings.toString(),
    });
    _checkForUpdatesIfHome(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    logUserAction('nav_replace', {
      'new': newRoute?.settings.name ?? '?',
      'old': oldRoute?.settings.name ?? '?',
    });
    _checkForUpdatesIfHome(newRoute);
  }

  void _checkForUpdatesIfHome(Route<dynamic>? route) {
    if (route == null) {
      return;
    }

    // Проверяем, является ли это главным экраном (путь "/")
    final routeSettings = route.settings;
    final routeName = routeSettings.name;

    // Проверяем обновления только при переходе на главный экран
    if (routeName != '/' && routeName != null && !routeName.startsWith('/')) {
      return; // Не главный экран, пропускаем проверку
    }

    // Используем Future.microtask чтобы не блокировать навигацию
    // Сохраняем ссылку на navigator до async операции
    final navigator = route.navigator;
    Future.microtask(() {
      try {
        // Получаем контекст из route после микротаска
        final navigatorContext = navigator?.context;
        if (navigatorContext == null) {
          return;
        }

        // Проверяем обновления при навигации на главный экран
        try {
          Provider.of<AppUpdateService>(
            // ignore: use_build_context_synchronously
            navigatorContext,
            listen: false,
          ).checkForUpdates();
        } catch (_) {}
        // Обновляем список чатов при возврате на главный экран
        try {
          Provider.of<ChatListRefreshService>(
            // ignore: use_build_context_synchronously
            navigatorContext,
            listen: false,
          ).requestRefresh();
        } catch (_) {}
      } catch (_) {
        // Игнорируем ошибки если сервис недоступен или контекст недоступен
      }
    });
  }
}
