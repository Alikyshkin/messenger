class User {
  final int id;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final String? publicKey;
  final String? email;

  /// День рождения в формате YYYY-MM-DD.
  final String? birthday;

  /// Номер телефона (только цифры).
  final String? phone;

  /// Количество друзей (контактов). Видно только число; список видит только владелец.
  final int? friendsCount;

  /// Онлайн-статус пользователя
  final bool? isOnline;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.publicKey,
    this.email,
    this.birthday,
    this.phone,
    this.friendsCount,
    this.isOnline,
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
      birthday: json['birthday'] as String?,
      phone: json['phone'] as String?,
      friendsCount: json['friends_count'] as int?,
      isOnline: json['is_online'] as bool?,
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
    String? birthday,
    String? phone,
    int? friendsCount,
    bool? isOnline,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      publicKey: publicKey ?? this.publicKey,
      email: email ?? this.email,
      birthday: birthday ?? this.birthday,
      phone: phone ?? this.phone,
      friendsCount: friendsCount ?? this.friendsCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
