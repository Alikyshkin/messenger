/// Заглушка для платформ, отличных от Web
class AppUpdateServiceWeb {
  static Future<void> reloadWithCacheClear() async {
    // Ничего не делаем на не-Web платформах
  }
}
