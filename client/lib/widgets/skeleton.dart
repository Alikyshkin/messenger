import 'package:flutter/material.dart';

/// Простой скелетон-прямоугольник (серый с закруглением).
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Скелетон строки чата в списке.
class SkeletonChatTile extends StatelessWidget {
  const SkeletonChatTile({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color,
      ),
      title: SkeletonBox(
        width: 140,
        height: 16,
        borderRadius: 4,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SkeletonBox(
          width: 200,
          height: 14,
          borderRadius: 4,
        ),
      ),
    );
  }
}

/// Скелетон строки контакта.
class SkeletonContactTile extends StatelessWidget {
  const SkeletonContactTile({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color,
      ),
      title: SkeletonBox(
        width: 120,
        height: 16,
        borderRadius: 4,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SkeletonBox(
          width: 160,
          height: 12,
          borderRadius: 4,
        ),
      ),
    );
  }
}

/// Скелетон пузыря сообщения (слева или справа).
class SkeletonMessageBubble extends StatelessWidget {
  final bool isRight;

  const SkeletonMessageBubble({super.key, this.isRight = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(width: 120, height: 14, borderRadius: 6),
            const SizedBox(height: 8),
            SkeletonBox(width: 60, height: 10, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}
