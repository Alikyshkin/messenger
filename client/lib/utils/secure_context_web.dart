// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Проверка безопасного контекста в браузере (HTTPS или localhost).
/// getUserMedia/WebRTC требуют secure context.
bool get isSecureContext => html.window.isSecureContext;
