import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_update_service.dart';

/// Виджет для отслеживания lifecycle приложения и проверки обновлений
class AppUpdateLifecycleListener extends StatefulWidget {
  final Widget child;

  const AppUpdateLifecycleListener({super.key, required this.child});

  @override
  State<AppUpdateLifecycleListener> createState() =>
      _AppUpdateLifecycleListenerState();
}

class _AppUpdateLifecycleListenerState extends State<AppUpdateLifecycleListener>
    with WidgetsBindingObserver {
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Проверяем обновления при запуске приложения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Проверяем обновления при возврате из фонового режима
    if (state == AppLifecycleState.resumed && _wasInBackground) {
      _checkForUpdates();
      _wasInBackground = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _wasInBackground = true;
    }
  }

  void _checkForUpdates() {
    if (!mounted) {
      return;
    }

    try {
      final updateService = Provider.of<AppUpdateService>(
        context,
        listen: false,
      );
      updateService.checkForUpdates();
    } catch (_) {
      // Игнорируем ошибки если сервис недоступен
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
