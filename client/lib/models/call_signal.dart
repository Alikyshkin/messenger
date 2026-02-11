/// Сигнал сигналинга звонка (offer, answer, ice, hangup, reject)
class CallSignal {
  final int fromUserId;
  final String signal; // 'offer' | 'answer' | 'ice' | 'hangup' | 'reject'
  final Map<String, dynamic>? payload;
  final bool? isVideoCall; // true для видеозвонка, false для голосового, null для совместимости
  final int? groupId; // ID группы для групповых звонков, null для приватных

  CallSignal({
    required this.fromUserId,
    required this.signal,
    this.payload,
    this.isVideoCall,
    this.groupId,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      fromUserId: json['fromUserId'] as int,
      signal: json['signal'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      isVideoCall: json['isVideoCall'] as bool?,
      groupId: json['groupId'] as int?,
    );
  }
}
