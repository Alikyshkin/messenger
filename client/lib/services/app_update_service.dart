import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart' show apiBaseUrl;
import '../config/version.dart' show AppVersion;
import 'app_update_service_stub.dart'
    if (dart.library.html) 'app_update_service_web.dart';

/// Сервис для проверки обновлений приложения
class AppUpdateService extends ChangeNotifier {
  String? _latestVersion;
  String? _currentVersion;
  bool _hasUpdate = false;
  Timer? _checkTimer;
  DateTime? _lastCheckTime;
  bool _isChecking = false;
  static const Duration _minCheckInterval = Duration(seconds: 30); // Минимальный интервал между проверками
  
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  bool get hasUpdate => _hasUpdate;
  
  AppUpdateService() {
    _init();
  }
  
  Future<void> _init() async {
    // Получаем текущую версию приложения
    if (kIsWeb) {
      // На Web версия берется из конфигурации
      _currentVersion = AppVersion.displayVersion;
    } else {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        _currentVersion = packageInfo.version;
      } catch (_) {
        // Fallback на версию из конфигурации
        _currentVersion = AppVersion.displayVersion;
      }
    }
    
    // Начинаем периодическую проверку обновлений
    _startPeriodicCheck();
    
    // Проверяем сразу при запуске
    checkForUpdates();
  }
  
  /// Запускает периодическую проверку обновлений (каждые 5 минут)
  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      checkForUpdates();
    });
  }
  
  /// Проверяет наличие обновлений на сервере
  /// Использует троттлинг чтобы не проверять слишком часто
  Future<void> checkForUpdates() async {
    // Если уже идет проверка, пропускаем
    if (_isChecking) return;
    
    // Если прошло недостаточно времени с последней проверки, пропускаем
    if (_lastCheckTime != null) {
      final timeSinceLastCheck = DateTime.now().difference(_lastCheckTime!);
      if (timeSinceLastCheck < _minCheckInterval) {
        return;
      }
    }
    
    _isChecking = true;
    _lastCheckTime = DateTime.now();
    
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/version'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final serverVersion = data['version'] as String?;
        
        if (serverVersion != null && serverVersion != _currentVersion) {
          _latestVersion = serverVersion;
          _hasUpdate = true;
          notifyListeners();
        } else {
          _hasUpdate = false;
          notifyListeners();
        }
      }
    } catch (_) {
      // Игнорируем ошибки проверки обновлений
    } finally {
      _isChecking = false;
    }
  }
  
  /// Закрывает уведомление об обновлении (без обновления)
  void dismissUpdate() {
    _hasUpdate = false;
    notifyListeners();
  }
  
  /// Обновляет приложение (перезагружает страницу на Web)
  Future<void> updateApp() async {
    if (kIsWeb) {
      // На Web перезагружаем страницу с очисткой кеша
      await AppUpdateServiceWeb.reloadWithCacheClear();
    }
    // На других платформах можно добавить логику обновления через store
  }
  
  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}
