import 'dart:async';
import 'dart:io';
import '../services/api.dart';
import 'error_utils.dart';

/// Утилиты для retry API запросов при временных ошибках
class ApiRetry {
  /// Выполняет API запрос с повторными попытками при временных ошибках
  ///
  /// [fn] - функция, выполняющая API запрос
  /// [maxAttempts] - максимальное количество попыток (по умолчанию 3)
  /// [initialDelay] - начальная задержка между попытками в секундах (по умолчанию 1)
  /// [maxDelay] - максимальная задержка в секундах (по умолчанию 10)
  static Future<T> retry<T>({
    required Future<T> Function() fn,
    int maxAttempts = 3,
    int initialDelay = 1,
    int maxDelay = 10,
  }) async {
    int attempt = 0;
    int delaySeconds = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await fn();
      } catch (e) {
        attempt++;

        // Если это последняя попытка или ошибка не retryable, выбрасываем ошибку
        if (attempt >= maxAttempts || !_isRetryableError(e)) {
          rethrow;
        }

        // Ждем перед следующей попыткой (экспоненциальный backoff)
        await Future.delayed(Duration(seconds: delaySeconds));
        delaySeconds = (delaySeconds * 2).clamp(initialDelay, maxDelay);
      }
    }

    throw Exception('Failed after $maxAttempts attempts');
  }

  /// Проверяет, можно ли повторить запрос при данной ошибке
  static bool _isRetryableError(dynamic error) {
    // Сетевые ошибки можно повторить
    if (ErrorUtils.isNetworkError(error)) {
      return true;
    }

    // Временные ошибки сервера (503, 502, 504) можно повторить
    if (error is ApiException) {
      final statusCode = error.statusCode;
      return statusCode == 503 || // Service Unavailable
          statusCode == 502 || // Bad Gateway
          statusCode == 504 || // Gateway Timeout
          statusCode == 429; // Too Many Requests (rate limiting)
    }

    // SocketException и другие сетевые ошибки
    if (error is SocketException) {
      return true;
    }

    return false;
  }
}
