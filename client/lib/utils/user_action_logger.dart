import 'package:flutter/foundation.dart';

/// Логирование действий пользователя в консоль для отладки.
/// Видно в DevTools / браузерной консоли (F12).
void logUserAction(String action, [Map<String, dynamic>? details]) {
  final ts = DateTime.now().toIso8601String();
  final detailStr = details != null && details.isNotEmpty
      ? ' ${details.entries.map((e) => '${e.key}=${e.value}').join(', ')}'
      : '';
  debugPrint('[UserAction] $ts | $action$detailStr');
}

/// Логирование ошибки при действии пользователя
void logUserActionError(String action, Object error, [StackTrace? stack]) {
  final ts = DateTime.now().toIso8601String();
  debugPrint('[UserAction] $ts | ERROR: $action');
  debugPrint('[UserAction]   → $error');
  if (stack != null) {
    debugPrint('[UserAction]   → $stack');
  }
}
