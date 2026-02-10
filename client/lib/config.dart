import 'package:flutter/foundation.dart';

/// Base URL API.
/// На вебе — тот же хост, что и у страницы, порт 3000.
/// Если задан dart-define API_BASE_URL — используется он (удобно для проверки против удалённого сервера).
/// На мобильных/десктопе — 127.0.0.1. Для эмулятора Android замените на 10.0.2.2:3000.
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) {
    return '${Uri.base.scheme}://${Uri.base.host}:3000';
  }
  return 'http://127.0.0.1:3000';
}

String get wsBaseUrl {
  final uri = Uri.parse(apiBaseUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 3000);
  return '$scheme://${uri.host}:$port/ws';
}
