import 'package:flutter/material.dart';
import '../services/api.dart';
import 'error_utils.dart';

/// Утилита для обработки ошибок в StatefulWidget
class ErrorHandler {
  /// Обрабатывает ошибку и обновляет состояние
  /// Возвращает true, если ошибка обработана и нужно выйти из функции
  static bool handleError(
    BuildContext context,
    dynamic error, {
    required void Function(String? error, bool loading) setState,
    String? Function(dynamic error)? getErrorMessage,
    bool showSnackBar = false,
  }) {
    if (!context.mounted) return true;

    String? errorMessage;

    if (error is ApiException) {
      errorMessage = error.message;
    } else if (getErrorMessage != null) {
      errorMessage = getErrorMessage(error);
    } else {
      errorMessage = ErrorUtils.getUserFriendlyMessage(error);
    }

    setState(errorMessage, false);

    if (showSnackBar && errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }

    return true;
  }

  /// Обрабатывает ошибку с показом SnackBar
  static void handleErrorWithSnackBar(
    BuildContext context,
    dynamic error, {
    String? Function(dynamic error)? getErrorMessage,
  }) {
    if (!context.mounted) return;

    String message;
    if (error is ApiException) {
      message = error.message;
    } else if (getErrorMessage != null) {
      message =
          getErrorMessage(error) ?? ErrorUtils.getUserFriendlyMessage(error);
    } else {
      message = ErrorUtils.getUserFriendlyMessage(error);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
