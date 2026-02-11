import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_update_service.dart';

/// NavigatorObserver для проверки обновлений при навигации
/// Проверяет обновления только при переходе на главный экран, чтобы не перегружать сервер
class NavigationUpdateObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // Проверяем обновления только при переходе на главный экран
    _checkForUpdatesIfHome(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // Проверяем обновления только при возврате на главный экран
    _checkForUpdatesIfHome(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    // Проверяем обновления только при переходе на главный экран
    _checkForUpdatesIfHome(newRoute);
  }

  void _checkForUpdatesIfHome(Route<dynamic>? route) {
    if (route == null) return;

    // Проверяем, является ли это главным экраном (путь "/")
    final routeSettings = route.settings;
    final routeName = routeSettings.name;

    // Проверяем обновления только при переходе на главный экран
    if (routeName != '/' && routeName != null && !routeName.startsWith('/')) {
      return; // Не главный экран, пропускаем проверку
    }

    // Используем Future.microtask чтобы не блокировать навигацию
    Future.microtask(() {
      try {
        // Получаем контекст из route после микротаска
        final navigatorContext = route.navigator?.context;
        if (navigatorContext == null) return;

        // Проверяем обновления при навигации на главный экран
        final updateService = Provider.of<AppUpdateService>(
          navigatorContext,
          listen: false,
        );
        updateService.checkForUpdates();
      } catch (_) {
        // Игнорируем ошибки если сервис недоступен или контекст недоступен
      }
    });
  }
}
