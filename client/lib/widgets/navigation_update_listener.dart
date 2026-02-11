import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_update_service.dart';

/// NavigatorObserver для проверки обновлений при навигации
class NavigationUpdateObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _checkForUpdates(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _checkForUpdates(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _checkForUpdates(newRoute);
  }

  void _checkForUpdates(Route<dynamic>? route) {
    if (route == null) return;
    
    // Используем Future.microtask чтобы не блокировать навигацию
    Future.microtask(() {
      try {
        // Получаем контекст из route после микротаска
        final navigatorContext = route.navigator?.context;
        if (navigatorContext == null) return;
        
        // Проверяем обновления при навигации
        final updateService = Provider.of<AppUpdateService>(navigatorContext, listen: false);
        updateService.checkForUpdates();
      } catch (_) {
        // Игнорируем ошибки если сервис недоступен или контекст недоступен
      }
    });
  }
}
