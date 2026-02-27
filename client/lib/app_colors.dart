import 'package:flutter/material.dart';

/// Telegram-style color palette.
class AppColors {
  AppColors._();

  // --- Telegram Blue ---
  static const Color primary = Color(0xFF2AABEE);

  // --- Light Theme ---
  static const Color lightPrimary = Color(0xFF2AABEE);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFE3F4FD);
  static const Color lightOnPrimaryContainer = Color(0xFF004B6B);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1A1A);
  static const Color lightSurfaceContainerHighest = Color(0xFFF1F3F4);
  static const Color lightOnSurfaceVariant = Color(0xFF707579);
  static const Color lightOutline = Color(0xFFE0E0E0);
  static const Color lightScaffoldBackground = Color(0xFFEFEFF4);
  static const Color lightError = Color(0xFFE53935);
  static const Color lightOnError = Color(0xFFFFFFFF);

  // Message bubble colors — light theme
  static const Color lightSentBubble = Color(0xFFEFFDDE);
  static const Color lightSentBubbleText = Color(0xFF1A1A1A);
  static const Color lightReceivedBubble = Color(0xFFFFFFFF);
  static const Color lightReceivedBubbleText = Color(0xFF1A1A1A);

  // --- Dark Theme ---
  static const Color darkPrimary = Color(0xFF6AB2D4);
  static const Color darkOnPrimary = Color(0xFFFFFFFF);
  static const Color darkPrimaryContainer = Color(0xFF1B3A5E);
  static const Color darkOnPrimaryContainer = Color(0xFF90CAF9);
  static const Color darkSurface = Color(0xFF232E3C);
  static const Color darkOnSurface = Color(0xFFE8EAED);
  static const Color darkSurfaceContainerHighest = Color(0xFF2B3744);
  static const Color darkOnSurfaceVariant = Color(0xFF8D9BA8);
  static const Color darkOutline = Color(0xFF394754);
  static const Color darkScaffoldBackground = Color(0xFF17212B);
  static const Color darkError = Color(0xFFEF5350);
  static const Color darkOnError = Color(0xFF212121);

  // Message bubble colors — dark theme
  static const Color darkSentBubble = Color(0xFF2B5278);
  static const Color darkSentBubbleText = Color(0xFFE8EAED);
  static const Color darkReceivedBubble = Color(0xFF182533);
  static const Color darkReceivedBubbleText = Color(0xFFE8EAED);
}
