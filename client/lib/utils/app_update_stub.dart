/// Заглушка для платформ, отличных от Web
class AppUpdateWeb {
  static Future<void> checkAndReloadIfNeeded() async {}
  static void forceReloadWithCacheClear() {}
  static Future<void> clearCache() async {}
}
