class FriendRequest {
  final int id;
  final int fromUserId;
  final String username;
  final String displayName;
  final String? createdAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.username,
    required this.displayName,
    this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as int,
      fromUserId: json['from_user_id'] as int,
      username: json['username'] as String,
      displayName: (json['display_name'] ?? json['username']) as String,
      createdAt: json['created_at'] as String?,
    );
  }
}

class OutgoingFriendRequest {
  final int id;
  final int toUserId;
  final String username;
  final String displayName;
  final String? createdAt;

  OutgoingFriendRequest({
    required this.id,
    required this.toUserId,
    required this.username,
    required this.displayName,
    this.createdAt,
  });

  factory OutgoingFriendRequest.fromJson(Map<String, dynamic> json) {
    return OutgoingFriendRequest(
      id: json['id'] as int,
      toUserId: json['to_user_id'] as int,
      username: json['username'] as String,
      displayName: (json['display_name'] ?? json['username']) as String,
      createdAt: json['created_at'] as String?,
    );
  }
}
