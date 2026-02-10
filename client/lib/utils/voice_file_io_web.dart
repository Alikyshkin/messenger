import 'dart:html' as html;
import 'dart:typed_data';

/// Читает байты голосового файла. На вебе [path] — это blob URL от record_web.
Future<Uint8List> readVoiceFileBytes(String path) async {
  final request = await html.HttpRequest.request(
    path,
    responseType: 'arraybuffer',
  );
  final buffer = request.response as ByteBuffer?;
  if (buffer == null) throw Exception('Не удалось прочитать запись');
  return Uint8List.view(buffer);
}
