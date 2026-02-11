import 'package:flutter/material.dart';
import '../models/user.dart';

/// Переиспользуемый виджет для отображения аватара пользователя
class UserAvatar extends StatelessWidget {
  final User? user;
  final double radius;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final String? fallbackText;
  final bool showOnlineIndicator;

  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.backgroundColor,
    this.textStyle,
    this.fallbackText,
    this.showOnlineIndicator = false,
  });

  /// Создает аватар из URL аватара или имени пользователя
  const UserAvatar.fromUrl({
    super.key,
    required String? avatarUrl,
    required String displayName,
    this.radius = 24,
    this.backgroundColor,
    this.textStyle,
    this.fallbackText,
  }) : user = null;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;
    final displayName = user?.displayName ?? fallbackText ?? '?';
    final bgColor =
        backgroundColor ?? Theme.of(context).colorScheme.primaryContainer;
    final style =
        textStyle ??
        TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w600,
        );

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: style,
            )
          : null,
    );

    if (!showOnlineIndicator || user?.isOnline != true) {
      return avatar;
    }

    // Индикатор онлайн - зеленая точка в правом нижнем углу
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: radius * 0.35,
            height: radius * 0.35,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
