import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'temp_file.dart';

/// Сохраняет байты во временный файл и открывает его (скачивание на десктопе/мобильных).
Future<void> saveOrDownloadFile(Uint8List bytes, String filename) async {
  final path = await writeTempBytes(bytes, filename);
  final uri = Uri.file(path);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
