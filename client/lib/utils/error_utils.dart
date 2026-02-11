import '../services/api.dart';

/// Утилиты для обработки ошибок
class ErrorUtils {
  /// Проверяет, является ли ошибка сетевой (нет интернета, таймаут и т.д.)
  static bool isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('socketexception') ||
        errorStr.contains('timeoutexception') ||
        errorStr.contains('httpexception') ||
        errorStr.contains('clientexception') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection timed out') ||
        errorStr.contains('no address associated with hostname');
  }

  /// Получает понятное сообщение об ошибке для пользователя
  static String getUserFriendlyMessage(dynamic error) {
    if (error is ApiException) {
      return error.message;
    }

    if (isNetworkError(error)) {
      return 'Нет подключения к интернету. Проверьте соединение и попробуйте снова.';
    }

    return error.toString();
  }

  /// Проверяет, является ли ошибка критической (требует повторной попытки)
  static bool isRetryableError(dynamic error) {
    if (error is ApiException) {
      // 5xx ошибки обычно можно повторить
      return error.statusCode >= 500 && error.statusCode < 600;
    }

    // Сетевые ошибки можно повторить
    return isNetworkError(error);
  }
}
