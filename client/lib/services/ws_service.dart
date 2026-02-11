import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/message.dart';
import '../models/call_signal.dart';

class ReactionUpdate {
  final int messageId;
  final int? peerId;
  final int? groupId;
  final List<MessageReaction> reactions;
  ReactionUpdate({required this.messageId, this.peerId, this.groupId, required this.reactions});
}

class _ReactionUpdate {
  final int messageId;
  final int? peerId;
  final int? groupId;
  final List<MessageReaction> reactions;
  _ReactionUpdate({required this.messageId, this.peerId, this.groupId, required this.reactions});
}

class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  String _token = '';
  bool _allowReconnect = true;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 30; // Максимальная задержка переподключения (секунды)
  final List<Message> _incoming = [];
  final List<_ReactionUpdate> _reactionUpdates = [];
  final List<Map<String, dynamic>> _pendingCallSignals = []; // Очередь сигналов звонка при отсутствии соединения
  final StreamController<CallSignal> _callSignalController = StreamController<CallSignal>.broadcast();
  final StreamController<void> _newMessageController = StreamController<void>.broadcast();
  final StreamController<Message> _newMessagePayloadController = StreamController<Message>.broadcast();

  bool get connected => _connected;
  List<Message> get pendingIncoming => List.unmodifiable(_incoming);
  Stream<CallSignal> get callSignals => _callSignalController.stream;
  /// Срабатывает при получении любого нового сообщения (чтобы обновить список чатов и счётчик непрочитанных).
  Stream<void> get onNewMessage => _newMessageController.stream;
  /// То же сообщение с данными (для уведомлений и звука).
  Stream<Message> get onNewMessageWithPayload => _newMessagePayloadController.stream;

  void connect(String token) {
    if (_token == token && _connected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    disconnect();
    _token = token;
    _allowReconnect = token.isNotEmpty;
    if (token.isEmpty) return;
    _doConnect();
  }

  void _doConnect() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    final uri = Uri.parse('$wsBaseUrl?token=$_token');
    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          _connected = false;
          _reconnectAttempts++;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          _connected = false;
          _reconnectAttempts++;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      _connected = true;
      _reconnectAttempts = 0; // Сбрасываем счетчик при успешном подключении
      _flushPendingCallSignals(); // Отправляем накопленные сигналы
      notifyListeners();
    } catch (_) {
      _connected = false;
      _reconnectAttempts++;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_allowReconnect || _token.isEmpty) return;
    _reconnectTimer?.cancel();
    // Экспоненциальный backoff: 3s, 6s, 12s, 24s, максимум 30s
    final delaySeconds = _reconnectAttempts == 0 
        ? 3 
        : (_reconnectAttempts <= 4 
            ? (3 * (1 << (_reconnectAttempts - 1)))
            : _maxReconnectDelay).clamp(3, _maxReconnectDelay);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      if (!_connected && _allowReconnect && _token.isNotEmpty) _doConnect();
    });
  }

  /// Отправляет накопленные сигналы звонка после переподключения
  void _flushPendingCallSignals() {
    if (!_connected || _channel == null || _pendingCallSignals.isEmpty) return;
    final signals = List<Map<String, dynamic>>.from(_pendingCallSignals);
    _pendingCallSignals.clear();
    for (final signal in signals) {
      try {
        _channel!.sink.add(jsonEncode(signal));
      } catch (_) {
        // Если не удалось отправить, возвращаем в очередь
        _pendingCallSignals.add(signal);
      }
    }
  }

  void _onMessage(dynamic data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      if (map['type'] == 'new_message' && map['message'] != null) {
        final msg = Message.fromJson(map['message'] as Map<String, dynamic>);
        _incoming.add(msg);
        notifyListeners();
        if (!_newMessageController.isClosed) _newMessageController.add(null);
        if (!_newMessagePayloadController.isClosed) _newMessagePayloadController.add(msg);
      } else if (map['type'] == 'new_group_message' && map['group_id'] != null && map['message'] != null) {
        final msgMap = map['message'] as Map<String, dynamic>;
        msgMap['group_id'] = map['group_id'];
        final msg = Message.fromJson(msgMap);
        _incoming.add(msg);
        notifyListeners();
        if (!_newMessageController.isClosed) _newMessageController.add(null);
        if (!_newMessagePayloadController.isClosed) _newMessagePayloadController.add(msg);
      } else if (map['type'] == 'call_signal' && map['fromUserId'] != null && map['signal'] != null) {
        _callSignalController.add(CallSignal.fromJson(map));
      } else if (map['type'] == 'reaction' && map['message_id'] != null && map['peer_id'] != null && map['reactions'] != null) {
        final reactions = _parseReactions(map['reactions']);
        _reactionUpdates.add(_ReactionUpdate(
          messageId: map['message_id'] as int,
          peerId: map['peer_id'] as int,
          reactions: reactions,
        ));
        notifyListeners();
      } else if (map['type'] == 'group_reaction' && map['group_id'] != null && map['message_id'] != null && map['reactions'] != null) {
        final reactions = _parseReactions(map['reactions']);
        _reactionUpdates.add(_ReactionUpdate(
          messageId: map['message_id'] as int,
          groupId: map['group_id'] as int,
          reactions: reactions,
        ));
        notifyListeners();
      }
    } catch (_) {}
  }

  static List<MessageReaction> _parseReactions(dynamic v) {
    if (v is! List) return [];
    final list = <MessageReaction>[];
    for (final e in v) {
      if (e is! Map<String, dynamic>) continue;
      final emoji = e['emoji'] as String?;
      final ids = e['user_ids'];
      if (emoji == null || emoji.isEmpty) continue;
      final userIds = ids is List
          ? (ids.map((x) => x is int ? x : (x is num ? x.toInt() : null)).whereType<int>().toList())
          : <int>[];
      list.add(MessageReaction(emoji: emoji, userIds: userIds));
    }
    return list;
  }

  void sendCallSignal(int toUserId, String signal, [Map<String, dynamic>? payload, bool? isVideoCall, int? groupId]) {
    final message = {
      'type': 'call_signal',
      'toUserId': toUserId,
      'signal': signal,
      if (payload != null) 'payload': payload,
      if (isVideoCall != null) 'isVideoCall': isVideoCall,
      if (groupId != null) 'groupId': groupId,
    };
    
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
        return;
      } catch (_) {
        // Если отправка не удалась, добавляем в очередь
      }
    }
    
    // Если соединение отсутствует или отправка не удалась, сохраняем в очередь
    // (кроме hangup/reject - их не нужно сохранять)
    if (signal != 'hangup' && signal != 'reject') {
      _pendingCallSignals.add(message);
    }
  }
  
  /// Отправить групповой сигнал звонка всем участникам группы
  void sendGroupCallSignal(int groupId, String signal, [Map<String, dynamic>? payload, bool? isVideoCall]) {
    final message = {
      'type': 'group_call_signal',
      'groupId': groupId,
      'signal': signal,
      if (payload != null) 'payload': payload,
      if (isVideoCall != null) 'isVideoCall': isVideoCall,
    };
    
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
        return;
      } catch (_) {
        // Если отправка не удалась, добавляем в очередь
      }
    }
    
    // Если соединение отсутствует или отправка не удалась, сохраняем в очередь
    // (кроме hangup/reject - их не нужно сохранять)
    if (signal != 'hangup' && signal != 'reject') {
      _pendingCallSignals.add(message);
    }
  }

  Message? takeIncomingFor(int peerId) {
    final i = _incoming.indexWhere((m) => m.groupId == null && (m.senderId == peerId || m.receiverId == peerId));
    if (i < 0) return null;
    return _incoming.removeAt(i);
  }

  Message? takeIncomingGroupFor(int groupId) {
    final i = _incoming.indexWhere((m) => m.groupId == groupId);
    if (i < 0) return null;
    return _incoming.removeAt(i);
  }

  ReactionUpdate? takeReactionUpdateFor(int peerId) {
    final i = _reactionUpdates.indexWhere((u) => u.peerId == peerId && u.groupId == null);
    if (i < 0) return null;
    final u = _reactionUpdates.removeAt(i);
    notifyListeners();
    return ReactionUpdate(messageId: u.messageId, peerId: u.peerId, reactions: u.reactions);
  }

  ReactionUpdate? takeGroupReactionUpdateFor(int groupId) {
    final i = _reactionUpdates.indexWhere((u) => u.groupId == groupId);
    if (i < 0) return null;
    final u = _reactionUpdates.removeAt(i);
    notifyListeners();
    return ReactionUpdate(messageId: u.messageId, groupId: u.groupId, reactions: u.reactions);
  }

  void clearPending() {
    _incoming.clear();
    _reactionUpdates.clear();
    notifyListeners();
  }

  void disconnect() {
    _allowReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _connected = false;
    _incoming.clear();
    _reactionUpdates.clear();
    _pendingCallSignals.clear();
    notifyListeners();
  }
}
