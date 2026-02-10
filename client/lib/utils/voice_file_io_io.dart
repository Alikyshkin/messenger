import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readVoiceFileBytes(String path) async {
  final bytes = await File(path).readAsBytes();
  return Uint8List.fromList(bytes);
}
