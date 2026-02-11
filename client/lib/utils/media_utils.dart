import 'package:flutter/foundation.dart';

/// Утилиты для работы с медиа (камера, микрофон)
class MediaUtils {
  /// Формирует сообщение об ошибке медиа в понятном для пользователя виде
  static String getMediaErrorMessage(Object e) {
    final errorStr = e.toString().toLowerCase();
    
    // Проверка для Web платформы
    if (kIsWeb) {
      if (errorStr.contains('null') || 
          errorStr.contains('getusermedia') || 
          errorStr.contains('media')) {
        return 'Видеозвонок в браузере доступен только по HTTPS. Откройте сайт по https:// или используйте приложение на телефоне.';
      }
    }
    
    // Проверка на отсутствие разрешений
    if (errorStr.contains('permission denied') ||
        errorStr.contains('notallowederror') ||
        errorStr.contains('permission')) {
      return 'Нет доступа к камере или микрофону. Разрешите доступ в настройках.';
    }
    
    // Проверка на отсутствие устройств
    if (errorStr.contains('notfounderror') ||
        errorStr.contains('devicesnotfounderror')) {
      return 'Камера/микрофон не найдены';
    }
    
    return e.toString();
  }

  /// Создает ограничения для видео с учетом платформы и устройства
  static Map<String, dynamic> buildVideoConstraints({
    required bool isFrontCamera,
    String? videoDeviceId,
  }) {
    final Map<String, dynamic> baseConstraints = kIsWeb
        ? {
            'mandatory': {
              'minWidth': '640',
              'minHeight': '480',
              'minFrameRate': '24',
            },
            'facingMode': isFrontCamera ? 'user' : 'environment',
            'optional': [],
          }
        : {
            'facingMode': isFrontCamera ? 'user' : 'environment',
            'width': {'ideal': 1280, 'min': 640},
            'height': {'ideal': 720, 'min': 480},
            'frameRate': {'ideal': 30, 'min': 24},
          };

    final constraints = Map<String, dynamic>.from(baseConstraints);
    
    // Добавляем выбор конкретного устройства, если указано
    if (videoDeviceId != null && videoDeviceId.isNotEmpty) {
      if (kIsWeb) {
        constraints['optional'] = [
          {'sourceId': videoDeviceId}
        ];
      } else {
        constraints['deviceId'] = {'exact': videoDeviceId};
      }
    }
    
    return constraints;
  }
}
