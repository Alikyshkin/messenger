import 'package:flutter/material.dart';

/// Цвета приложения в одном месте — меняются из одного файла.
/// Material Blue #2196F3 — популярный синий, как в Telegram, Messenger.
class AppColors {
  AppColors._();

  // --- Material Blue #2196F3 ---
  static const Color primaryBlue = Color(0xFF2196F3);

  // --- Светлая тема ---
  static const Color lightPrimary = Color(0xFF2196F3);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFBBDEFB);
  static const Color lightOnPrimaryContainer = Color(0xFF0D47A1);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1A1A);
  static const Color lightSurfaceContainerHighest = Color(0xFFF0F2F5);
  static const Color lightOnSurfaceVariant = Color(0xFF5C5C5C);
  static const Color lightOutline = Color(0xFFD0D4D9);
  static const Color lightScaffoldBackground = Color(0xFFE8EAED);
  static const Color lightError = Color(0xFFC62828);
  static const Color lightOnError = Color(0xFFFFFFFF);

  // --- Тёмная тема ---
  static const Color darkPrimary = Color(0xFF42A5F5);
  static const Color darkOnPrimary = Color(0xFF0D47A1);
  static const Color darkPrimaryContainer = Color(0xFF1565C0);
  static const Color darkOnPrimaryContainer = Color(0xFFBBDEFB);
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkOnSurface = Color(0xFFE8EAED);
  static const Color darkSurfaceContainerHighest = Color(0xFF2A2D31);
  static const Color darkOnSurfaceVariant = Color(0xFFA0A4A8);
  static const Color darkOutline = Color(0xFF4A4E52);
  static const Color darkScaffoldBackground = Color(0xFF121212);
  static const Color darkError = Color(0xFFE57373);
  static const Color darkOnError = Color(0xFF1A1A1A);
}
