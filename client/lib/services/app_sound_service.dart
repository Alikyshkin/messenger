import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Воспроизведение звуков приложения: входящий звонок (рингтон), уведомление о сообщении.
class AppSoundService {
  AppSoundService._();
  static final AppSoundService instance = AppSoundService._();

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();

  bool _ringtonePlaying = false;
  bool get isRingtonePlaying => _ringtonePlaying;

  bool _inCall = false;
  void setInCall(bool value) => _inCall = value;

  Future<void> _initPlayers() async {
    try {
      await _ringtonePlayer.setLoopMode(LoopMode.one);
      await _ringtonePlayer.setVolume(0.8);
      await _notificationPlayer.setVolume(0.7);
    } catch (_) {}
  }

  /// Запускает рингтон (входящий звонок) в цикле.
  Future<void> playRingtone() async {
    if (_ringtonePlaying) {
      return;
    }
    await _initPlayers();
    try {
      await _ringtonePlayer.setAsset(
        'assets/sounds/ringtone.wav',
        initialPosition: Duration.zero,
      );
      await _ringtonePlayer.play();
      _ringtonePlaying = true;
    } catch (_) {
      if (kDebugMode) {
        // ignore: avoid_print
        debugPrint('AppSoundService: ringtone asset not found or failed');
      }
    }
  }

  /// Останавливает рингтон.
  Future<void> stopRingtone() async {
    if (!_ringtonePlaying) {
      return;
    }
    try {
      await _ringtonePlayer.stop();
      _ringtonePlaying = false;
    } catch (_) {}
  }

  /// Один раз проигрывает звук уведомления о новом сообщении.
  /// Не проигрывается во время активного звонка, чтобы не было писка в ухе.
  Future<void> playNotification() async {
    if (_inCall) {
      return;
    }
    await _initPlayers();
    try {
      await _notificationPlayer.setAsset(
        'assets/sounds/notification.wav',
        initialPosition: Duration.zero,
      );
      await _notificationPlayer.play();
    } catch (_) {
      if (kDebugMode) {
        // ignore: avoid_print
        debugPrint('AppSoundService: notification asset not found or failed');
      }
    }
  }

  void dispose() {
    _ringtonePlayer.dispose();
    _notificationPlayer.dispose();
  }
}
