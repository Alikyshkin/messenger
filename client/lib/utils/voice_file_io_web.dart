// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import '../utils/user_action_logger.dart';

/// Читает байты голосового файла. На вебе [path] может быть blob URL или data URI.
Future<Uint8List> readVoiceFileBytes(String path) async {
  final scope = logActionStart('voice_file_io_web', 'readVoiceFileBytes', {
    'path': path.length > 50 ? '${path.substring(0, 50)}...' : path,
    'isDataUri': path.startsWith('data:'),
    'isBlobUrl': path.startsWith('blob:'),
  });
  try {
    // Если это data URI, декодируем base64 напрямую
    if (path.startsWith('data:')) {
      final commaIndex = path.indexOf(',');
      if (commaIndex == -1) {
        scope.fail('invalid data URI format');
        throw Exception('Неверный формат data URI');
      }
      final base64Data = path.substring(commaIndex + 1);
      try {
        final bytes = base64Decode(base64Data);
        scope.end({'bytesLen': bytes.length, 'source': 'dataUri'});
        return bytes;
      } catch (e) {
        scope.fail(e);
        throw Exception('Ошибка декодирования data URI: $e');
      }
    }

    // Для blob URL или обычного URL используем HttpRequest
    // Проверяем, что path является валидным URL
    if (!path.startsWith('blob:') &&
        !path.startsWith('http://') &&
        !path.startsWith('https://')) {
      scope.fail('invalid URL format: $path');
      throw Exception('Неверный формат пути: $path');
    }

    try {
      final request = await html.HttpRequest.request(
        path,
        responseType: 'arraybuffer',
      );
      final buffer = request.response as ByteBuffer?;
      if (buffer == null) {
        scope.fail('buffer is null');
        throw Exception('Не удалось прочитать запись');
      }
      final bytes = Uint8List.view(buffer);
      scope.end({'bytesLen': bytes.length, 'source': 'httpRequest'});
      return bytes;
    } catch (e) {
      // Если это ошибка из-за CSP или другого ограничения браузера
      if (e.toString().contains('Namespace') || e.toString().contains('CSP')) {
        scope.fail('CSP or namespace error: $e');
        throw Exception(
          'Ошибка доступа к файлу (возможно, ограничение безопасности браузера): $e',
        );
      }
      rethrow;
    }
  } catch (e, st) {
    scope.fail(e, st);
    rethrow;
  }
}
