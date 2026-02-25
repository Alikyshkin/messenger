// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:typed_data';
import 'dart:html' as html;

/// Скачивает файл в браузере (сохранить как).
Future<void> saveOrDownloadFile(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}
