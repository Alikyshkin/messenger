import 'package:flutter/material.dart';

/// Кнопка управления медиа в звонке (микрофон, камера, демонстрация экрана)
/// Использует цвета из темы и показывает состояние (включено/выключено)
class CallControlButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final IconData? disabledIcon;
  final String? tooltip;
  final bool isEnabled;
  final Color? enabledColor;
  final Color? disabledColor;
  final double? size;

  const CallControlButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.disabledIcon,
    this.tooltip,
    required this.isEnabled,
    this.enabledColor,
    this.disabledColor,
    this.size,
  });

  /// Кнопка микрофона
  factory CallControlButton.microphone({
    required VoidCallback? onPressed,
    required bool isEnabled,
    String? tooltip,
  }) {
    return CallControlButton(
      onPressed: onPressed,
      icon: Icons.mic,
      disabledIcon: Icons.mic_off,
      tooltip: tooltip ?? (isEnabled ? 'Выключить микрофон' : 'Включить микрофон'),
      isEnabled: isEnabled,
    );
  }

  /// Кнопка камеры
  factory CallControlButton.camera({
    required VoidCallback? onPressed,
    required bool isEnabled,
    String? tooltip,
  }) {
    return CallControlButton(
      onPressed: onPressed,
      icon: Icons.videocam,
      disabledIcon: Icons.videocam_off,
      tooltip: tooltip ?? (isEnabled ? 'Выключить камеру' : 'Включить камеру'),
      isEnabled: isEnabled,
    );
  }

  /// Кнопка демонстрации экрана
  factory CallControlButton.screenShare({
    required VoidCallback? onPressed,
    required bool isEnabled,
    String? tooltip,
  }) {
    return CallControlButton(
      onPressed: onPressed,
      icon: Icons.screen_share,
      disabledIcon: Icons.stop_screen_share,
      tooltip: tooltip ?? (isEnabled ? 'Остановить демонстрацию' : 'Демонстрация экрана'),
      isEnabled: isEnabled,
      enabledColor: Colors.orange.shade700,
    );
  }

  /// Кнопка переключения камеры
  factory CallControlButton.switchCamera({
    required VoidCallback? onPressed,
    String? tooltip,
  }) {
    return CallControlButton(
      onPressed: onPressed,
      icon: Icons.flip_camera_ios,
      tooltip: tooltip ?? 'Переключить камеру',
      isEnabled: true,
    );
  }

  /// Кнопка участников/настроек
  factory CallControlButton.participants({
    required VoidCallback? onPressed,
    required bool isExpanded,
    String? tooltip,
  }) {
    return CallControlButton(
      onPressed: onPressed,
      icon: isExpanded ? Icons.keyboard_arrow_down : Icons.people,
      tooltip: tooltip ?? (isExpanded ? 'Скрыть' : 'Участники и настройки'),
      isEnabled: true,
      enabledColor: Colors.blue.shade700,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultSize = size ?? 56.0;
    final iconSize = size != null ? size! * 0.5 : 28.0;
    
    // Цвета по умолчанию из темы
    final defaultEnabledColor = enabledColor ?? 
        (theme.brightness == Brightness.dark 
            ? Colors.grey.shade700 
            : Colors.grey.shade600);
    final defaultDisabledColor = disabledColor ?? Colors.red.shade700;
    
    final backgroundColor = isEnabled ? defaultEnabledColor : defaultDisabledColor;
    final iconToShow = isEnabled ? icon : (disabledIcon ?? icon);
    
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(iconToShow),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: EdgeInsets.all(defaultSize * 0.25),
        minimumSize: Size(defaultSize, defaultSize),
        maximumSize: Size(defaultSize, defaultSize),
        iconSize: iconSize,
      ),
    );
  }
}
