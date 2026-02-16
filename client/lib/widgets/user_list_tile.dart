import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import '../utils/format_last_seen.dart';
import 'user_avatar.dart';

/// Унифицированный элемент списка пользователя
class UserListTile extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double avatarRadius;
  final bool showUsername;
  final bool showLastSeen;

  const UserListTile({
    super.key,
    required this.user,
    this.onTap,
    this.trailing,
    this.avatarRadius = AppSizes.avatarMD,
    this.showUsername = true,
    this.showLastSeen = false,
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
        showOnlineIndicator: true,
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: showUsername || showLastSeen
          ? Text(
              [
                if (showUsername) '@${user.username}',
                if (showLastSeen && (user.isOnline == true || (user.lastSeen != null && user.lastSeen!.isNotEmpty)))
                  formatLastSeen(context, user.lastSeen, user.isOnline),
              ].where((s) => s.isNotEmpty).join(' • '),
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
