import 'package:flutter/material.dart';
import 'minimized_call_widget.dart';

/// Overlay для отображения компактного звонка поверх любого экрана
/// Используется в MaterialApp для глобального отображения
class MinimizedCallOverlay extends StatelessWidget {
  final Widget child;

  const MinimizedCallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [child, const MinimizedCallWidget()]);
  }
}
