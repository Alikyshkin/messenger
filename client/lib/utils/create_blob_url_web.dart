// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Создает blob URL из bytes для воспроизведения аудио на веб.
Future<String?> createBlobUrlFromBytes(List<int> bytes, String mimeType) async {
  try {
    final blob = html.Blob([bytes], mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  } catch (_) {
    return null;
  }
}
