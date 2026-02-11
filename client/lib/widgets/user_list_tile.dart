import 'package:flutter/material.dart';
import '../models/user.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import 'user_avatar.dart';

/// Унифицированный элемент списка пользователя
class UserListTile extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double avatarRadius;
  final bool showUsername;

  const UserListTile({
    super.key,
    required this.user,
    this.onTap,
    this.trailing,
    this.avatarRadius = AppSizes.avatarMD,
    this.showUsername = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: AppSpacing.listItemPadding,
      leading: UserAvatar(
        user: user,
        radius: avatarRadius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        textStyle: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: showUsername
          ? Text(
              '@${user.username}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
