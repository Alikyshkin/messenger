import 'user.dart';

class LastMessage {
  final int id;
  final String content;
  final String createdAt;
  final bool isMine;
  final String messageType;

  LastMessage({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.messageType = 'text',
  });

  static LastMessage? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return LastMessage(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String,
      isMine: json['is_mine'] as bool? ?? false,
      messageType: json['message_type'] as String? ?? 'text',
    );
  }

  bool get isPoll => messageType == 'poll';
}

class ChatPreview {
  final User peer;
  final LastMessage? lastMessage;
  final int unreadCount;

  ChatPreview({required this.peer, this.lastMessage, this.unreadCount = 0});

  factory ChatPreview.fromJson(Map<String, dynamic> json) {
    return ChatPreview(
      peer: User.fromJson(json['peer'] as Map<String, dynamic>),
      lastMessage: LastMessage.fromJson(json['last_message'] as Map<String, dynamic>?),
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}
