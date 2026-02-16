import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Уровень качества сети для отображения в UI звонка.
enum NetworkQuality {
  /// Отличное: RTT < 150ms, потери < 1%
  excellent,

  /// Хорошее: RTT < 300ms, потери < 3%
  good,

  /// Среднее: RTT < 500ms, потери < 5%
  fair,

  /// Плохое: выше порогов
  poor,

  /// Неизвестно (нет данных)
  unknown,
}

/// Вычисляет уровень качества сети из WebRTC stats.
class CallNetworkQuality {
  /// RTT в секундах (currentRoundTripTime из candidate-pair)
  static double? _getRtt(List<StatsReport> reports) {
    for (final r in reports) {
      if (r.type == 'candidate-pair') {
        final v = r.values['currentRoundTripTime'];
        if (v != null) return (v as num).toDouble();
      }
    }
    return null;
  }

  /// Потеря пакетов в процентах (из inbound-rtp)
  static double? _getPacketLossPercent(List<StatsReport> reports) {
    int totalPackets = 0;
    int lost = 0;
    for (final r in reports) {
      if (r.type == 'inbound-rtp') {
        final received = r.values['packetsReceived'];
        final loss = r.values['packetsLost'];
        if (received != null && loss != null) {
          totalPackets += (received as num).toInt() + (loss as num).toInt();
          lost += (loss as num).toInt();
        }
      }
    }
    if (totalPackets == 0) return null;
    return 100.0 * lost / totalPackets;
  }

  /// Определяет уровень качества по RTT и потерям.
  static NetworkQuality fromStats(List<StatsReport> reports) {
    final rtt = _getRtt(reports);
    final loss = _getPacketLossPercent(reports);

    if (rtt == null && loss == null) return NetworkQuality.unknown;

    // Используем консервативную оценку: если нет RTT — считаем по loss
    final rttMs = rtt != null ? rtt * 1000 : 0.0;
    final lossPct = loss ?? 0.0;

    if (rttMs > 500 || lossPct > 5) return NetworkQuality.poor;
    if (rttMs > 300 || lossPct > 3) return NetworkQuality.fair;
    if (rttMs > 150 || lossPct > 1) return NetworkQuality.good;
    return NetworkQuality.excellent;
  }
}
