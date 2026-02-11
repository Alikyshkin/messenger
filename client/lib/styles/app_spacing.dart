import 'package:flutter/material.dart';

/// Константы отступов для единообразия UI
class AppSpacing {
  AppSpacing._();

  // Базовые отступы
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // Отступы для контента экранов
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(12, 12, 12, 24);
  static const EdgeInsets screenPaddingVertical = EdgeInsets.fromLTRB(12, 16, 12, 24);
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const EdgeInsets cardPaddingLarge = EdgeInsets.symmetric(vertical: 24, horizontal: 16);
  static const EdgeInsets sectionPadding = EdgeInsets.fromLTRB(16, 16, 16, 8);
  static const EdgeInsets inputPadding = EdgeInsets.all(16);
  static const EdgeInsets errorPadding = EdgeInsets.all(24);
  static const EdgeInsets emptyStatePadding = EdgeInsets.all(32);

  // Отступы для навигации
  static const EdgeInsets navigationPadding = EdgeInsets.symmetric(horizontal: 8);
  static const double navigationIconSize = 28.0;
  static const double navigationAvatarRadius = 20.0;

  // Отступы для списков
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const EdgeInsets listPadding = EdgeInsets.fromLTRB(12, 12, 12, 24);

  // Отступы между элементами
  static const SizedBox spacingXS = SizedBox(width: xs, height: xs);
  static const SizedBox spacingSM = SizedBox(width: sm, height: sm);
  static const SizedBox spacingMD = SizedBox(width: md, height: md);
  static const SizedBox spacingLG = SizedBox(width: lg, height: lg);
  static const SizedBox spacingXL = SizedBox(width: xl, height: xl);
  static const SizedBox spacingXXL = SizedBox(width: xxl, height: xxl);

  // Горизонтальные отступы
  static const SizedBox spacingHorizontalXS = SizedBox(width: xs);
  static const SizedBox spacingHorizontalSM = SizedBox(width: sm);
  static const SizedBox spacingHorizontalMD = SizedBox(width: md);
  static const SizedBox spacingHorizontalLG = SizedBox(width: lg);
  static const SizedBox spacingHorizontalXL = SizedBox(width: xl);

  // Вертикальные отступы
  static const SizedBox spacingVerticalXS = SizedBox(height: xs);
  static const SizedBox spacingVerticalSM = SizedBox(height: sm);
  static const SizedBox spacingVerticalMD = SizedBox(height: md);
  static const SizedBox spacingVerticalLG = SizedBox(height: lg);
  static const SizedBox spacingVerticalXL = SizedBox(height: xl);
  static const SizedBox spacingVerticalXXL = SizedBox(height: xxl);
}
