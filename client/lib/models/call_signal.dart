/// Сигнал сигналинга звонка (offer, answer, ice, hangup, reject)
class CallSignal {
  final int fromUserId;
  final String signal; // 'offer' | 'answer' | 'ice' | 'hangup' | 'reject'
  final Map<String, dynamic>? payload;

  CallSignal({
    required this.fromUserId,
    required this.signal,
    this.payload,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      fromUserId: json['fromUserId'] as int,
      signal: json['signal'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}
