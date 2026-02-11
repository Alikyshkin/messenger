import 'package:flutter/material.dart';

/// Аккуратный badge для навигации с адаптивными размерами
class NavBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color? textColor;

  const NavBadge({
    super.key,
    required this.count,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.error;
    final txtColor = textColor ?? theme.colorScheme.onError;

    // Адаптивные размеры в зависимости от количества цифр
    final isLarge = count > 9;
    final horizontalPadding = isLarge ? 6.0 : 5.0;
    final minWidth = isLarge ? 20.0 : 18.0;
    final fontSize = isLarge ? 10.0 : 11.0;

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 18),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: txtColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.0,
            letterSpacing: -0.2,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
