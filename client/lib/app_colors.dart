import 'package:flutter/material.dart';

/// Цвета приложения в одном месте — меняются из одного файла.
/// Jade #AEB8A0 — приглушённый зелёно-серый.
class AppColors {
  AppColors._();

  // --- Jade #AEB8A0 ---
  static const Color jade = Color(0xFFAEB8A0);

  // --- Светлая тема ---
  static const Color lightPrimary = Color(0xFFAEB8A0);
  static const Color lightOnPrimary = Color(0xFF1A1A1A);
  static const Color lightPrimaryContainer = Color(0xFFE2E6DC);
  static const Color lightOnPrimaryContainer = Color(0xFF1A1A1A);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1A1A);
  static const Color lightSurfaceContainerHighest = Color(0xFFF0F2F5);
  static const Color lightOnSurfaceVariant = Color(0xFF5C5C5C);
  static const Color lightOutline = Color(0xFFD0D4D9);
  static const Color lightScaffoldBackground = Color(0xFFE8EAED);
  static const Color lightError = Color(0xFFC62828);
  static const Color lightOnError = Color(0xFFFFFFFF);

  // --- Тёмная тема ---
  static const Color darkPrimary = Color(0xFFB8C4AA);
  static const Color darkOnPrimary = Color(0xFF1A1A1A);
  static const Color darkPrimaryContainer = Color(0xFF4A5540);
  static const Color darkOnPrimaryContainer = Color(0xFFE2E6DC);
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkOnSurface = Color(0xFFE8EAED);
  static const Color darkSurfaceContainerHighest = Color(0xFF2A2D31);
  static const Color darkOnSurfaceVariant = Color(0xFFA0A4A8);
  static const Color darkOutline = Color(0xFF4A4E52);
  static const Color darkScaffoldBackground = Color(0xFF121212);
  static const Color darkError = Color(0xFFE57373);
  static const Color darkOnError = Color(0xFF1A1A1A);
}
