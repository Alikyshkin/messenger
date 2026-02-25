import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/message.dart';
import '../models/call_signal.dart';
import '../utils/user_action_logger.dart';

class ReactionUpdate {
  final int messageId;
  final int? peerId;
  final int? groupId;
  final List<MessageReaction> reactions;
  ReactionUpdate({
    required this.messageId,
    this.peerId,
    this.groupId,
    required this.reactions,
  });
}

class EditMessageUpdate {
  final int messageId;
  final int peerId;
  final String content;
  EditMessageUpdate({
    required this.messageId,
    required this.peerId,
    required this.content,
  });
}

class DeleteMessageUpdate {
  final int messageId;
  final int peerId;
  DeleteMessageUpdate({required this.messageId, required this.peerId});
}

class TypingInfo {
  final String displayName;
  final DateTime at;
  TypingInfo({required this.displayName, required this.at});
}

class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  String _token = '';
  bool _allowReconnect = true;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay =
      30; // Максимальная задержка переподключения (секунды)
  final List<Message> _incoming = [];
  final List<ReactionUpdate> _reactionUpdates = [];
  final List<EditMessageUpdate> _editUpdates = [];
  final List<DeleteMessageUpdate> _deleteUpdates = [];
  final Map<int, TypingInfo> _peerTyping = {};
  final Map<int, Map<int, TypingInfo>> _groupTyping = {};
  Timer? _typingExpiryTimer;
  static const _typingTimeout = Duration(seconds: 5);
  final List<Map<String, dynamic>> _pendingCallSignals =
      []; // Очередь сигналов звонка при отсутствии соединения
  final StreamController<CallSignal> _callSignalController =
      StreamController<CallSignal>.broadcast();
  final StreamController<void> _newMessageController =
      StreamController<void>.broadcast();
  final StreamController<Message> _newMessagePayloadController =
      StreamController<Message>.broadcast();

  bool get connected => _connected;
  List<Message> get pendingIncoming => List.unmodifiable(_incoming);
  Stream<CallSignal> get callSignals => _callSignalController.stream;

  /// Срабатывает при получении любого нового сообщения (чтобы обновить список чатов и счётчик непрочитанных).
  Stream<void> get onNewMessage => _newMessageController.stream;

  /// То же сообщение с данными (для уведомлений и звука).
  Stream<Message> get onNewMessageWithPayload =>
      _newMessagePayloadController.stream;

  void connect(String token) {
    logAction('ws_service', 'connect', 'START', {
      'tokenLen': token.length,
      'wasConnected': _connected,
    });
    if (_token == token && _connected) {
      logAction('ws_service', 'connect', 'SKIP', {
        'reason': 'already_connected',
      });
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    disconnect();
    _token = token;
    _allowReconnect = token.isNotEmpty;
    if (token.isEmpty) {
      return;
    }
    _doConnect();
  }

  void _doConnect() {
    logAction('ws_service', '_doConnect', 'START', {
      'attempt': _reconnectAttempts,
    });
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
          logActionError('ws_service', '_doConnect_onError', e, {
            'attempt': _reconnectAttempts,
          });
          _connected = false;
          _reconnectAttempts++;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          logAction('ws_service', '_doConnect_onDone', 'done', {
            'attempt': _reconnectAttempts,
          });
          _connected = false;
          _reconnectAttempts++;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      _connected = true;
      _reconnectAttempts = 0; // Сбрасываем счетчик при успешном подключении
      logAction('ws_service', '_doConnect', 'END', null, 'connected');
      _flushPendingCallSignals(); // Отправляем накопленные сигналы
      notifyListeners();
    } catch (e) {
      logActionError('ws_service', '_doConnect', e);
      _connected = false;
      _reconnectAttempts++;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_allowReconnect || _token.isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    // Экспоненциальный backoff: 3s, 6s, 12s, 24s, максимум 30s
    final delaySeconds = _reconnectAttempts == 0
        ? 3
        : (_reconnectAttempts <= 4
                  ? (3 * (1 << (_reconnectAttempts - 1)))
                  : _maxReconnectDelay)
              .clamp(3, _maxReconnectDelay);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      if (!_connected && _allowReconnect && _token.isNotEmpty) {
        _doConnect();
      }
    });
  }

  /// Отправляет накопленные сигналы звонка после переподключения
  void _flushPendingCallSignals() {
    if (!_connected || _channel == null || _pendingCallSignals.isEmpty) {
      return;
    }
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
        if (!_newMessageController.isClosed) {
          _newMessageController.add(null);
        }
        if (!_newMessagePayloadController.isClosed) {
          _newMessagePayloadController.add(msg);
        }
      } else if (map['type'] == 'new_group_message' &&
          map['group_id'] != null &&
          map['message'] != null) {
        final msgMap = map['message'] as Map<String, dynamic>;
        msgMap['group_id'] = map['group_id'];
        final msg = Message.fromJson(msgMap);
        _incoming.add(msg);
        notifyListeners();
        if (!_newMessageController.isClosed) {
          _newMessageController.add(null);
        }
        if (!_newMessagePayloadController.isClosed) {
          _newMessagePayloadController.add(msg);
        }
      } else if (map['type'] == 'call_signal' &&
          map['fromUserId'] != null &&
          map['signal'] != null) {
        _callSignalController.add(CallSignal.fromJson(map));
      } else if (map['type'] == 'reaction' &&
          map['message_id'] != null &&
          map['peer_id'] != null &&
          map['reactions'] != null) {
        final reactions = _parseReactions(map['reactions']);
        _reactionUpdates.add(
          ReactionUpdate(
            messageId: map['message_id'] as int,
            peerId: map['peer_id'] as int,
            reactions: reactions,
          ),
        );
        notifyListeners();
      } else if (map['type'] == 'group_reaction' &&
          map['group_id'] != null &&
          map['message_id'] != null &&
          map['reactions'] != null) {
        final reactions = _parseReactions(map['reactions']);
        _reactionUpdates.add(
          ReactionUpdate(
            messageId: map['message_id'] as int,
            groupId: map['group_id'] as int,
            reactions: reactions,
          ),
        );
        notifyListeners();
      } else if (map['type'] == 'message_edited' &&
          map['message_id'] != null &&
          map['peer_id'] != null &&
          map['content'] != null) {
        _editUpdates.add(
          EditMessageUpdate(
            messageId: map['message_id'] as int,
            peerId: map['peer_id'] as int,
            content: map['content'] as String,
          ),
        );
        notifyListeners();
      } else if (map['type'] == 'message_deleted' &&
          map['message_id'] != null &&
          map['peer_id'] != null) {
        _deleteUpdates.add(
          DeleteMessageUpdate(
            messageId: map['message_id'] as int,
            peerId: map['peer_id'] as int,
          ),
        );
        notifyListeners();
      } else if (map['type'] == 'typing' &&
          map['fromUserId'] != null &&
          map['displayName'] != null) {
        final peerId = map['fromUserId'] as int;
        _peerTyping[peerId] = TypingInfo(
          displayName: map['displayName'] as String,
          at: DateTime.now(),
        );
        _startTypingExpiryTimer();
        notifyListeners();
      } else if (map['type'] == 'group_typing' &&
          map['groupId'] != null &&
          map['fromUserId'] != null &&
          map['displayName'] != null) {
        final groupId = map['groupId'] as int;
        final userId = map['fromUserId'] as int;
        _groupTyping.putIfAbsent(groupId, () => {});
        _groupTyping[groupId]![userId] = TypingInfo(
          displayName: map['displayName'] as String,
          at: DateTime.now(),
        );
        _startTypingExpiryTimer();
        notifyListeners();
      }
    } catch (_) {}
  }

  static List<MessageReaction> _parseReactions(dynamic v) {
    if (v is! List) {
      return [];
    }
    final list = <MessageReaction>[];
    for (final e in v) {
      if (e is! Map<String, dynamic>) continue;
      final emoji = e['emoji'] as String?;
      final ids = e['user_ids'];
      if (emoji == null || emoji.isEmpty) continue;
      final userIds = ids is List
          ? (ids
                .map((x) => x is int ? x : (x is num ? x.toInt() : null))
                .whereType<int>()
                .toList())
          : <int>[];
      list.add(MessageReaction(emoji: emoji, userIds: userIds));
    }
    return list;
  }

  void sendCallSignal(
    int toUserId,
    String signal, [
    Map<String, dynamic>? payload,
    bool? isVideoCall,
    int? groupId,
  ]) {
    final message = {
      'type': 'call_signal',
      'toUserId': toUserId,
      'signal': signal,
      ...?payload != null ? {'payload': payload} : null,
      ...?isVideoCall != null ? {'isVideoCall': isVideoCall} : null,
      ...?groupId != null ? {'groupId': groupId} : null,
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
  void sendTyping(int toUserId) {
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(
          jsonEncode({'type': 'typing', 'toUserId': toUserId}),
        );
      } catch (_) {}
    }
  }

  void sendGroupTyping(int groupId) {
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(
          jsonEncode({'type': 'group_typing', 'groupId': groupId}),
        );
      } catch (_) {}
    }
  }

  void sendGroupCallSignal(
    int groupId,
    String signal, [
    Map<String, dynamic>? payload,
    bool? isVideoCall,
  ]) {
    final message = {
      'type': 'group_call_signal',
      'groupId': groupId,
      'signal': signal,
      ...?payload != null ? {'payload': payload} : null,
      ...?isVideoCall != null ? {'isVideoCall': isVideoCall} : null,
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
    final i = _incoming.indexWhere(
      (m) =>
          m.groupId == null && (m.senderId == peerId || m.receiverId == peerId),
    );
    if (i < 0) {
      return null;
    }
    return _incoming.removeAt(i);
  }

  Message? takeIncomingGroupFor(int groupId) {
    final i = _incoming.indexWhere((m) => m.groupId == groupId);
    if (i < 0) {
      return null;
    }
    return _incoming.removeAt(i);
  }

  ReactionUpdate? takeReactionUpdateFor(int peerId) {
    final i = _reactionUpdates.indexWhere(
      (u) => u.peerId == peerId && u.groupId == null,
    );
    if (i < 0) {
      return null;
    }
    final u = _reactionUpdates.removeAt(i);
    notifyListeners();
    return u;
  }

  ReactionUpdate? takeGroupReactionUpdateFor(int groupId) {
    final i = _reactionUpdates.indexWhere((u) => u.groupId == groupId);
    if (i < 0) {
      return null;
    }
    final u = _reactionUpdates.removeAt(i);
    notifyListeners();
    return u;
  }

  EditMessageUpdate? takeEditUpdateFor(int peerId) {
    final i = _editUpdates.indexWhere((u) => u.peerId == peerId);
    if (i < 0) {
      return null;
    }
    final u = _editUpdates.removeAt(i);
    notifyListeners();
    return u;
  }

  DeleteMessageUpdate? takeDeleteUpdateFor(int peerId) {
    final i = _deleteUpdates.indexWhere((u) => u.peerId == peerId);
    if (i < 0) {
      return null;
    }
    final u = _deleteUpdates.removeAt(i);
    notifyListeners();
    return u;
  }

  void _startTypingExpiryTimer() {
    _typingExpiryTimer?.cancel();
    _typingExpiryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      var changed = false;
      _peerTyping.removeWhere((_, v) {
        if (now.difference(v.at) > _typingTimeout) {
          changed = true;
          return true;
        }
        return false;
      });
      for (final entry in _groupTyping.entries.toList()) {
        entry.value.removeWhere((_, v) {
          if (now.difference(v.at) > _typingTimeout) {
            changed = true;
            return true;
          }
          return false;
        });
        if (entry.value.isEmpty) {
          _groupTyping.remove(entry.key);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  /// Текст "печатает" для личного чата (null если никто не печатает).
  String? getPeerTyping(int peerId) {
    final info = _peerTyping[peerId];
    if (info == null) return null;
    if (DateTime.now().difference(info.at) > _typingTimeout) return null;
    return info.displayName;
  }

  /// Список имён "печатают" для группы.
  List<String> getGroupTyping(int groupId) {
    final users = _groupTyping[groupId];
    if (users == null) return [];
    final now = DateTime.now();
    return users.entries
        .where((e) => now.difference(e.value.at) <= _typingTimeout)
        .map((e) => e.value.displayName)
        .toList();
  }

  void clearPending() {
    _incoming.clear();
    _reactionUpdates.clear();
    _editUpdates.clear();
    _deleteUpdates.clear();
    notifyListeners();
  }

  void disconnect() {
    logAction('ws_service', 'disconnect', 'done');
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
    _editUpdates.clear();
    _deleteUpdates.clear();
    _pendingCallSignals.clear();
    _typingExpiryTimer?.cancel();
    _typingExpiryTimer = null;
    _peerTyping.clear();
    _groupTyping.clear();
    notifyListeners();
  }
}
