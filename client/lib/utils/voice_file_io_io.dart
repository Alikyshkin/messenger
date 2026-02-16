import 'dart:io';
import 'dart:typed_data';
import '../utils/user_action_logger.dart';

Future<Uint8List> readVoiceFileBytes(String path) async {
  final scope = logActionStart('voice_file_io_io', 'readVoiceFileBytes', {'path': path});
  try {
    final bytes = await File(path).readAsBytes();
    scope.end({'bytesLen': bytes.length});
    return Uint8List.fromList(bytes);
  } catch (e, st) {
    scope.fail(e, st);
    rethrow;
  }
}
