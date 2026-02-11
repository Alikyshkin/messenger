import 'package:flutter/material.dart';

/// Кнопка переключения режима отображения в звонке
/// Использует цвета из темы для единообразия
class CallLayoutButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final Color? selectedColor;
  final Color? unselectedColor;

  const CallLayoutButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Цвета по умолчанию из темы
    final defaultSelectedColor = selectedColor ?? 
        (theme.brightness == Brightness.dark 
            ? Colors.blue.shade700 
            : Colors.blue.shade600);
    final defaultUnselectedColor = unselectedColor ?? 
        (theme.brightness == Brightness.dark 
            ? Colors.grey.shade800 
            : Colors.grey.shade700);
    
    final backgroundColor = isSelected ? defaultSelectedColor : defaultUnselectedColor;
    
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
      ),
    );
  }
}
