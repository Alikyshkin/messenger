import 'package:flutter/material.dart';

/// Заметная кнопка «Назад» для AppBar — показывает, что экран открыт поверх другого и можно вернуться.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    if (!canPop) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.25),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 24,
              color: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
