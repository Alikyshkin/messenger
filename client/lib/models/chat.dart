import 'user.dart';
import 'group.dart';

class LastMessage {
  final int id;
  final String content;
  final String createdAt;
  final bool isMine;
  final String messageType;
  final String? senderDisplayName;

  LastMessage({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.isMine,
    this.messageType = 'text',
    this.senderDisplayName,
  });

  static LastMessage? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return LastMessage(
      id: json['id'] as int,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String,
      isMine: json['is_mine'] as bool? ?? false,
      messageType: json['message_type'] as String? ?? 'text',
      senderDisplayName: json['sender_display_name'] as String?,
    );
  }

  bool get isPoll => messageType == 'poll';
}

class ChatPreview {
  final User? peer;
  final Group? group;
  final LastMessage? lastMessage;
  final int unreadCount;

  ChatPreview({this.peer, this.group, this.lastMessage, this.unreadCount = 0});

  bool get isGroup => group != null;

  factory ChatPreview.fromJson(Map<String, dynamic> json) {
    User? peer;
    Group? group;
    if (json['peer'] != null) {
      peer = User.fromJson(json['peer'] as Map<String, dynamic>);
    }
    if (json['group'] != null) {
      group = Group.fromJson(json['group'] as Map<String, dynamic>);
    }
    return ChatPreview(
      peer: peer,
      group: group,
      lastMessage: LastMessage.fromJson(
        json['last_message'] as Map<String, dynamic>?,
      ),
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}
