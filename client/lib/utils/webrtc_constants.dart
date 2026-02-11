/// Общие константы для WebRTC соединений
class WebRTCConstants {
  /// Конфигурация ICE серверов для WebRTC
  static const iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// Минимальные требования к видео для Web
  static const webVideoConstraints = {
    'mandatory': {
      'minWidth': '640',
      'minHeight': '480',
      'minFrameRate': '24',
    },
  };

  /// Минимальные требования к видео для мобильных платформ
  static const mobileVideoConstraints = {
    'width': {'ideal': 1280, 'min': 640},
    'height': {'ideal': 720, 'min': 480},
    'frameRate': {'ideal': 30, 'min': 24},
  };
}
