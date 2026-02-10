/// Заглушка кэша вложений (веб и платформы без доступа к файлам).
Future<List<int>?> getCachedAttachmentBytes(int peerId, int messageId, String filename) async =>
    null;

Future<void> putCachedAttachment(int peerId, int messageId, String filename, List<int> bytes) async {}

Future<void> clearAttachmentCacheForChat(int peerId) async {}

Future<void> clearAllAttachmentCache() async {}

Future<int> getAttachmentCacheSizeBytes() async => 0;
