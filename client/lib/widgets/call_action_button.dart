import 'package:flutter/material.dart';

/// Кнопка действия в звонке (принять, отклонить, завершить)
/// Использует цвета из темы для единообразия
class CallActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  /// Поворот иконки в радианах (для выпрямления call_end и т.п.)
  final double? iconRotation;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? size;
  final EdgeInsetsGeometry? padding;

  const CallActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.iconRotation,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.size,
    this.padding,
  });

  /// Кнопка для принятия звонка (зеленая)
  factory CallActionButton.accept({
    required VoidCallback? onPressed,
    required IconData icon,
    String? tooltip,
    double? size,
  }) {
    return CallActionButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      size: size,
    );
  }

  /// Кнопка для отклонения/завершения звонка (красная)
  /// Иконка call_end по дизайну наклонена — выпрямляем для аккуратного вида
  factory CallActionButton.reject({
    required VoidCallback? onPressed,
    String? tooltip,
    double? size,
    EdgeInsetsGeometry? padding,
  }) {
    return CallActionButton(
      onPressed: onPressed,
      icon: Icons.call_end_rounded,
      tooltip: tooltip,
      backgroundColor: Colors.red,
      foregroundColor: Colors.white,
      size: size,
      padding: padding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultSize = size ?? 56.0;
    final iconSize = size != null ? size! * 0.5 : 28.0;
    final defaultPadding = padding ?? EdgeInsets.all(defaultSize * 0.25);

    Widget iconWidget = Icon(icon);
    if (iconRotation != null && iconRotation != 0) {
      iconWidget = Transform.rotate(angle: iconRotation!, child: iconWidget);
    }
    return IconButton.filled(
      onPressed: onPressed,
      icon: iconWidget,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor ?? theme.colorScheme.primary,
        foregroundColor: foregroundColor ?? theme.colorScheme.onPrimary,
        padding: defaultPadding,
        minimumSize: Size(defaultSize, defaultSize),
        maximumSize: Size(defaultSize, defaultSize),
        iconSize: iconSize,
      ),
    );
  }
}
