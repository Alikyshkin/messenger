import 'package:flutter/material.dart';

/// Плавный переход между экранами: лёгкое появление и сдвиг снизу.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget Function(BuildContext) builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const curve = Curves.easeOutCubic;
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: curve,
          );
          final opacityAnimation = Tween<double>(
            begin: 0,
            end: 1,
          ).animate(curvedAnimation);
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curvedAnimation);
          return FadeTransition(
            opacity: opacityAnimation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
      );
}
