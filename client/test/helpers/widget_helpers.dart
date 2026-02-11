import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/locale_service.dart';
import 'package:client/services/theme_service.dart';
import 'package:client/services/ws_service.dart';

/// Сбрасывает SharedPreferences для тестов.
Future<void> initTestPreferences() async {
  SharedPreferences.setMockInitialValues({});
}

/// Оборачивает [child] в MaterialApp и провайдеры, нужные для экранов мессенджера.
Widget wrapWithApp({
  required Widget child,
  AuthService? authService,
  LocaleService? localeService,
  ThemeService? themeService,
  WsService? wsService,
}) {
  final auth = authService ?? AuthService();
  final locale = localeService ?? LocaleService();
  final theme = themeService ?? ThemeService();
  final ws = wsService ?? WsService();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<LocaleService>.value(value: locale),
      ChangeNotifierProvider<ThemeService>.value(value: theme),
      ChangeNotifierProvider<WsService>.value(value: ws),
    ],
    child: MaterialApp(
      locale: locale.locale ?? const Locale('ru'),
      theme: ThemeData(useMaterial3: true),
      home: child,
    ),
  );
}
