/// Константы размеров для единообразия UI
class AppSizes {
  AppSizes._();

  /// Ширина экрана, ниже которой считается мобильный режим (боковая панель → нижняя навигация)
  static const double mobileBreakpoint = 600;

  /// Ширина экрана для компактного режима (уменьшенные отступы)
  static const double compactBreakpoint = 400;

  /// Проверка: мобильный режим (узкий экран)
  static bool isMobile(double width) => width < mobileBreakpoint;

  /// Проверка: компактный режим (очень узкий экран)
  static bool isCompact(double width) => width < compactBreakpoint;

  /// Высота нижней навигации (с учётом safe area)
  static const double bottomNavHeight = 56.0;

  // Размеры иконок
  static const double iconXS = 16.0;
  static const double iconSM = 18.0;
  static const double iconMD = 20.0;
  static const double iconLG = 24.0;
  static const double iconXL = 28.0;
  static const double iconXXL = 32.0;
  static const double iconXXXL = 48.0;

  // Радиусы аватаров
  static const double avatarXS = 16.0;
  static const double avatarSM = 20.0;
  static const double avatarMD = 24.0;
  static const double avatarLG = 28.0;
  static const double avatarXL = 48.0;

  // Радиусы скругления
  static const double radiusXS = 4.0;
  static const double radiusSM = 8.0;
  static const double radiusMD = 10.0;
  static const double radiusLG = 12.0;

  // Высота элементов
  static const double appBarHeight = 56.0;
  static const double buttonHeight = 40.0;
  static const double inputHeight = 48.0;

  // Ширина элементов
  static const double navigationWidth = 72.0;
  static const double navigationIconSize = 28.0;
  static const double badgeMinWidth = 20.0;

  // Размеры индикаторов загрузки
  static const double loadingIndicatorSize = 20.0;
  static const double loadingIndicatorStrokeWidth = 2.0;
}
