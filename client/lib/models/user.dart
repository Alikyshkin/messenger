class User {
  final int id;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? publicKey;
  final String? email;
  /// Количество друзей (контактов). Видно только число; список видит только владелец.
  final int? friendsCount;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.publicKey,
    this.email,
    this.friendsCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      displayName: (json['display_name'] ?? json['username']) as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      publicKey: json['public_key'] as String?,
      email: json['email'] as String?,
      friendsCount: json['friends_count'] as int?,
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? publicKey,
    String? email,
    int? friendsCount,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      publicKey: publicKey ?? this.publicKey,
      email: email ?? this.email,
      friendsCount: friendsCount ?? this.friendsCount,
    );
  }
}
