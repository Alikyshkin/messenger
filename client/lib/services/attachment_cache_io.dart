import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _cacheDirName = 'messenger_attachment_cache';

String _safeFilename(String name) {
  if (name.isEmpty) return 'файл';
  return name
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}

Future<Directory> _cacheRoot() async {
  final dir = await getApplicationDocumentsDirectory();
  return Directory(p.join(dir.path, _cacheDirName));
}

Future<List<int>?> getCachedAttachmentBytes(
  int peerId,
  int messageId,
  String filename,
) async {
  final root = await _cacheRoot();
  final file = File(
    p.join(root.path, '$peerId', '${messageId}_${_safeFilename(filename)}'),
  );
  if (await file.exists()) {
    return file.readAsBytes();
  }
  return null;
}

Future<void> putCachedAttachment(
  int peerId,
  int messageId,
  String filename,
  List<int> bytes,
) async {
  final root = await _cacheRoot();
  final peerDir = Directory(p.join(root.path, '$peerId'));
  if (!await peerDir.exists()) await peerDir.create(recursive: true);
  final file = File(
    p.join(peerDir.path, '${messageId}_${_safeFilename(filename)}'),
  );
  await file.writeAsBytes(bytes);
}

Future<void> clearAttachmentCacheForChat(int peerId) async {
  final root = await _cacheRoot();
  final peerDir = Directory(p.join(root.path, '$peerId'));
  if (await peerDir.exists()) await peerDir.delete(recursive: true);
}

Future<void> clearAllAttachmentCache() async {
  final root = await _cacheRoot();
  if (await root.exists()) await root.delete(recursive: true);
}

Future<int> getAttachmentCacheSizeBytes() async {
  final root = await _cacheRoot();
  if (!await root.exists()) return 0;
  int total = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}
