import 'package:flutter/foundation.dart';

/// Base URL API.
/// На вебе — тот же хост и порт, что и у страницы (запросы идут через nginx; при HTTPS порт 443).
/// Если задан dart-define API_BASE_URL — используется он (удобно для проверки против удалённого сервера).
/// На мобильных/десктопе — 127.0.0.1. Для эмулятора Android замените на 10.0.2.2:3000.
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) {
    return Uri.base.origin;
  }
  return 'http://127.0.0.1:3000';
}

String get wsBaseUrl {
  final uri = Uri.parse(apiBaseUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final isDefaultPort = (scheme == 'wss' && port == 443) || (scheme == 'ws' && (port == 80 || port == 3000));
  if (isDefaultPort) return '$scheme://${uri.host}/ws';
  return '$scheme://${uri.host}:$port/ws';
}
