class User {
  final int id;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? publicKey;
  final String? email;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.publicKey,
    this.email,
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
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      publicKey: publicKey ?? this.publicKey,
      email: email ?? this.email,
    );
  }
}
