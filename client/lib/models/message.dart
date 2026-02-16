import 'dart:convert';

class MessageReaction {
  final String emoji;
  final List<int> userIds;
  MessageReaction({required this.emoji, required this.userIds});
  int get count => userIds.length;
}

class Message {
  final int id;
  final int senderId;
  final int receiverId;
  final int? groupId;
  final String content;
  final String createdAt;
  final String? readAt;
  final bool isMine;
  final String? attachmentUrl;
  final String? attachmentFilename;
  final String messageType;
  final int? pollId;
  final PollData? poll;
  final String attachmentKind;
  final int? attachmentDurationSec;
  final String? senderPublicKey;
  final String? senderDisplayName;
  final bool attachmentEncrypted;
  final int? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final bool isForwarded;
  final int? forwardFromSenderId;
  final String? forwardFromDisplayName;
  final List<MessageReaction> reactions;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.groupId,
    required this.content,
    required this.createdAt,
    this.readAt,
    required this.isMine,
    this.attachmentUrl,
    this.attachmentFilename,
    this.messageType = 'text',
    this.pollId,
    this.poll,
    this.attachmentKind = 'file',
    this.attachmentDurationSec,
    this.senderPublicKey,
    this.senderDisplayName,
    this.attachmentEncrypted = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.isForwarded = false,
    this.forwardFromSenderId,
    this.forwardFromDisplayName,
    this.reactions = const [],
  });

  bool get isGroupMessage => groupId != null;

  Message copyWith({String? content, List<MessageReaction>? reactions}) {
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      groupId: groupId,
      content: content ?? this.content,
      createdAt: createdAt,
      readAt: readAt,
      isMine: isMine,
      attachmentUrl: attachmentUrl,
      attachmentFilename: attachmentFilename,
      messageType: messageType,
      pollId: pollId,
      poll: poll,
      attachmentKind: attachmentKind,
      attachmentDurationSec: attachmentDurationSec,
      senderPublicKey: senderPublicKey,
      senderDisplayName: senderDisplayName,
      attachmentEncrypted: attachmentEncrypted,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      isForwarded: isForwarded,
      forwardFromSenderId: forwardFromSenderId,
      forwardFromDisplayName: forwardFromDisplayName,
      reactions: reactions ?? this.reactions,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    PollData? poll;
    if (json['poll'] != null) {
      final p = json['poll'] as Map<String, dynamic>;
      final opts =
          (p['options'] as List<dynamic>?)?.map((e) {
            final o = e as Map<String, dynamic>;
            return PollOption(
              text: o['text'] as String,
              votes: o['votes'] as int? ?? 0,
              voted: o['voted'] as bool? ?? false,
            );
          }).toList() ??
          [];
      poll = PollData(
        id: p['id'] as int,
        question: p['question'] as String? ?? '',
        options: opts,
        multiple: p['multiple'] as bool? ?? false,
      );
    }
    return Message(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int? ?? 0,
      groupId: json['group_id'] as int?,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String,
      readAt: json['read_at'] as String?,
      isMine: json['is_mine'] as bool? ?? false,
      attachmentUrl: json['attachment_url'] as String?,
      attachmentFilename: json['attachment_filename'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      pollId: json['poll_id'] as int?,
      poll: poll,
      attachmentKind: json['attachment_kind'] as String? ?? 'file',
      attachmentDurationSec: json['attachment_duration_sec'] as int?,
      senderPublicKey: json['sender_public_key'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      attachmentEncrypted: json['attachment_encrypted'] as bool? ?? false,
      replyToId: json['reply_to_id'] as int?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      isForwarded: json['is_forwarded'] as bool? ?? false,
      forwardFromSenderId: json['forward_from_sender_id'] as int?,
      forwardFromDisplayName: json['forward_from_display_name'] as String?,
      reactions: _parseReactions(json['reactions']),
    );
  }

  static List<MessageReaction> _parseReactions(dynamic v) {
    if (v is! List) {
      return [];
    }
    final list = <MessageReaction>[];
    for (final e in v) {
      if (e is! Map<String, dynamic>) continue;
      final emoji = e['emoji'] as String?;
      final ids = e['user_ids'];
      if (emoji == null || emoji.isEmpty) continue;
      final userIds = ids is List
          ? (ids
                .map((x) => (x is int) ? x : (x is num ? x.toInt() : null))
                .whereType<int>()
                .toList())
          : <int>[];
      list.add(MessageReaction(emoji: emoji, userIds: userIds));
    }
    return list;
  }

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get isPoll => messageType == 'poll' && poll != null;
  bool get isVoice => attachmentKind == 'voice' && attachmentUrl != null;
  bool get isVideoNote =>
      attachmentKind == 'video_note' && attachmentUrl != null;
  bool get isLocation => messageType == 'location';

  /// Парсит content как JSON для location-сообщений. Возвращает null, если не location или невалидный JSON.
  ({double lat, double lng, String? label})? get locationData =>
      Message.parseLocationContent(content);

  /// Парсит content как JSON для location-сообщений.
  static ({double lat, double lng, String? label})? parseLocationContent(
      String content) {
    if (content.isEmpty || !content.startsWith('{')) return null;
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (
        lat: lat,
        lng: lng,
        label: m['label'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class PollData {
  final int id;
  final String question;
  final List<PollOption> options;
  final bool multiple;
  PollData({
    required this.id,
    required this.question,
    required this.options,
    required this.multiple,
  });
}

class PollOption {
  final String text;
  final int votes;
  final bool voted;
  PollOption({required this.text, required this.votes, required this.voted});
}
