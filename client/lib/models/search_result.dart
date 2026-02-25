/// Результат поиска по сообщениям.
class SearchMessageItem {
  final int id;
  final int senderId;
  final int receiverId;
  final int? groupId;
  final String? groupName;
  final int? peerId;
  final String? peerDisplayName;
  final String? senderDisplayName;
  final String content;
  final String createdAt;
  final bool isMine;
  final String messageType;
  final String? attachmentUrl;
  final String? attachmentFilename;
  final String attachmentKind;
  final int? attachmentDurationSec;
  final bool attachmentEncrypted;

  SearchMessageItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.groupId,
    this.groupName,
    this.peerId,
    this.peerDisplayName,
    this.senderDisplayName,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.messageType = 'text',
    this.attachmentUrl,
    this.attachmentFilename,
    this.attachmentKind = 'file',
    this.attachmentDurationSec,
    this.attachmentEncrypted = false,
  });

  factory SearchMessageItem.fromJson(Map<String, dynamic> json) {
    final peer = json['peer'] as Map<String, dynamic>?;
    return SearchMessageItem(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      groupId: json['group_id'] as int?,
      groupName: json['group_name'] as String?,
      peerId: peer?['id'] as int?,
      peerDisplayName: peer?['display_name'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String,
      isMine: json['is_mine'] as bool? ?? false,
      messageType: json['message_type'] as String? ?? 'text',
      attachmentUrl: json['attachment_url'] as String?,
      attachmentFilename: json['attachment_filename'] as String?,
      attachmentKind: json['attachment_kind'] as String? ?? 'file',
      attachmentDurationSec: json['attachment_duration_sec'] as int?,
      attachmentEncrypted: json['attachment_encrypted'] as bool? ?? false,
    );
  }

  bool get isGroup => groupId != null;
}

class SearchMessagesResult {
  final List<SearchMessageItem> data;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  SearchMessagesResult({
    required this.data,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory SearchMessagesResult.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final list = json['data'] as List<dynamic>? ?? [];
    return SearchMessagesResult(
      data: list
          .map((e) => SearchMessageItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: pagination['total'] as int? ?? 0,
      limit: pagination['limit'] as int? ?? 50,
      offset: pagination['offset'] as int? ?? 0,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }
}
