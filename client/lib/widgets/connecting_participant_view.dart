import 'package:flutter/material.dart';
import '../models/user.dart';
import 'user_avatar.dart';

/// Виджет для отображения участника в процессе подключения
class ConnectingParticipantView extends StatelessWidget {
  final User user;
  final double avatarRadius;
  final double fontSize;
  final bool showConnectingText;

  const ConnectingParticipantView({
    super.key,
    required this.user,
    this.avatarRadius = 60,
    this.fontSize = 24,
    this.showConnectingText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          UserAvatar(
            user: user,
            radius: avatarRadius,
            backgroundColor: Colors.blue.shade700,
            textStyle: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            user.displayName,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showConnectingText) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Подключение...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }
}
