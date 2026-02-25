import 'package:flutter/foundation.dart';

/// Скурпулёзное логирование: файл, действие, фаза (старт/конец/ошибка), детали, причина.
/// Видно в DevTools / браузерной консоли (F12).

String _ts() => DateTime.now().toIso8601String();

String _fmt(
  String file,
  String action,
  String phase, [
  Map<String, dynamic>? details,
  String? reason,
]) {
  final parts = <String>['[$file]', _ts(), action, '|', phase];
  if (details != null && details.isNotEmpty) {
    parts.add('|');
    parts.add(details.entries.map((e) => '${e.key}=${e.value}').join(', '));
  }
  if (reason != null && reason.isNotEmpty) {
    parts.add('|');
    parts.add(reason);
  }
  return parts.join(' ');
}

/// Логирование действия пользователя (простой вариант, для обратной совместимости).
void logUserAction(String action, [Map<String, dynamic>? details]) {
  logAction('user_action', action, 'done', details);
}

/// Логирование ошибки при действии пользователя.
void logUserActionError(String action, Object error, [StackTrace? stack]) {
  logActionError('user_action', action, error, null, stack);
}

/// Начало действия — вызывать в начале функции/обработчика.
/// Возвращает [ActionLogScope] для вызова [ActionLogScope.end] или [ActionLogScope.fail].
ActionLogScope logActionStart(
  String file,
  String action, [
  Map<String, dynamic>? details,
]) {
  debugPrint(_fmt(file, action, 'START', details));
  return ActionLogScope._(file, action, DateTime.now(), details);
}

/// Конец действия — вызывать при успешном завершении.
void logActionEnd(
  String file,
  String action, [
  Map<String, dynamic>? details,
  Duration? duration,
]) {
  final d = duration != null ? '${duration.inMilliseconds}ms' : null;
  final m = <String, dynamic>{if (d != null) 'duration': d}
    ..addAll(details ?? {});
  debugPrint(_fmt(file, action, 'END', m.isNotEmpty ? m : null, 'ok'));
}

/// Ошибка действия — вызывать при исключении.
void logActionError(
  String file,
  String action,
  Object error, [
  Map<String, dynamic>? details,
  StackTrace? stack,
]) {
  debugPrint(_fmt(file, action, 'ERROR', details, error.toString()));
  if (stack != null) {
    debugPrint('[$file] $action | STACK: $stack');
  }
}

/// Универсальный лог: файл, действие, фаза (START/END/ERROR/done), детали.
void logAction(
  String file,
  String action,
  String phase, [
  Map<String, dynamic>? details,
  String? reason,
]) {
  debugPrint(_fmt(file, action, phase, details, reason));
}

/// Область действия для логирования — автоматически замеряет duration при end/fail.
class ActionLogScope {
  ActionLogScope._(this._file, this._action, this._start, this._details);

  final String _file;
  final String _action;
  final DateTime _start;
  final Map<String, dynamic>? _details;

  void end([Map<String, dynamic>? extra]) {
    final d = DateTime.now().difference(_start);
    final m = <String, dynamic>{'duration': '${d.inMilliseconds}ms'}
      ..addAll(_details ?? {})
      ..addAll(extra ?? {});
    debugPrint(_fmt(_file, _action, 'END', m, 'ok'));
  }

  void fail(Object error, [StackTrace? stack]) {
    final d = DateTime.now().difference(_start);
    final m = <String, dynamic>{'duration': '${d.inMilliseconds}ms'}
      ..addAll(_details ?? {});
    logActionError(_file, _action, error, m, stack);
  }
}
