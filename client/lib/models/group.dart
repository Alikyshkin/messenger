class Group {
  final int id;
  final String name;
  final String? avatarUrl;
  final int createdByUserId;
  final String createdAt;
  final String? myRole;
  final int? memberCount;
  final List<GroupMember>? members;

  Group({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.createdByUserId,
    required this.createdAt,
    this.myRole,
    this.memberCount,
    this.members,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    List<GroupMember>? members;
    if (json['members'] != null) {
      final list = json['members'] as List<dynamic>;
      members = list
          .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return Group(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdByUserId: json['created_by_user_id'] as int? ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      myRole: json['my_role'] as String?,
      memberCount: json['member_count'] as int?,
      members: members,
    );
  }
}

class GroupMember {
  final int id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? publicKey;
  final String role;

  GroupMember({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.publicKey,
    this.role = 'member',
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      displayName:
          json['display_name'] as String? ?? json['username'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      publicKey: json['public_key'] as String?,
      role: json['role'] as String? ?? 'member',
    );
  }
}
