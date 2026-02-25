import 'package:flutter/material.dart';

/// Цвета приложения в одном месте — в стиле Signal (зелёный/бирюзовый акцент, минимум декора).
class AppColors {
  AppColors._();

  // --- Акцент Signal: зелёный/бирюзовый ---
  static const Color primary = Color(0xFF2C6B4F);

  // --- Светлая тема ---
  static const Color lightPrimary = Color(0xFF2C6B4F);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFE0F2EB);
  static const Color lightOnPrimaryContainer = Color(0xFF1B4332);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1A1A);
  static const Color lightSurfaceContainerHighest = Color(0xFFF0F2F5);
  static const Color lightOnSurfaceVariant = Color(0xFF5C5C5C);
  static const Color lightOutline = Color(0xFFD0D4D9);
  static const Color lightScaffoldBackground = Color(0xFFF5F7F5);
  static const Color lightError = Color(0xFFC62828);
  static const Color lightOnError = Color(0xFFFFFFFF);

  // --- Тёмная тема ---
  static const Color darkPrimary = Color(0xFF3A9D7B);
  static const Color darkOnPrimary = Color(0xFFFFFFFF);
  static const Color darkPrimaryContainer = Color(0xFF1B4332);
  static const Color darkOnPrimaryContainer = Color(0xFFB8E0D0);
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkOnSurface = Color(0xFFE8EAED);
  static const Color darkSurfaceContainerHighest = Color(0xFF2A2D31);
  static const Color darkOnSurfaceVariant = Color(0xFFA0A4A8);
  static const Color darkOutline = Color(0xFF4A4E52);
  static const Color darkScaffoldBackground = Color(0xFF121212);
  static const Color darkError = Color(0xFFE57373);
  static const Color darkOnError = Color(0xFF1A1A1A);
}
