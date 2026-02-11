/// Сигнал сигналинга звонка (offer, answer, ice, hangup, reject)
class CallSignal {
  final int fromUserId;
  final String signal; // 'offer' | 'answer' | 'ice' | 'hangup' | 'reject'
  final Map<String, dynamic>? payload;
  final bool?
  isVideoCall; // true для видеозвонка, false для голосового, null для совместимости
  final int? groupId; // ID группы для групповых звонков, null для приватных

  CallSignal({
    required this.fromUserId,
    required this.signal,
    this.payload,
    this.isVideoCall,
    this.groupId,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    // Правильно парсим isVideoCall: может быть bool, string, или null
    bool? isVideoCall;
    final isVideoCallValue = json['isVideoCall'];
    if (isVideoCallValue != null) {
      if (isVideoCallValue is bool) {
        isVideoCall = isVideoCallValue;
      } else if (isVideoCallValue is String) {
        // Обрабатываем строковые значения "true"/"false"
        isVideoCall = isVideoCallValue.toLowerCase() == 'true';
      } else if (isVideoCallValue is int) {
        // Обрабатываем числовые значения (0 = false, 1 = true)
        isVideoCall = isVideoCallValue != 0;
      }
    }

    return CallSignal(
      fromUserId: json['fromUserId'] as int,
      signal: json['signal'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      isVideoCall: isVideoCall,
      groupId: json['groupId'] as int?,
    );
  }
}
