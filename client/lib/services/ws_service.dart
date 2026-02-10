import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/message.dart';
import '../models/call_signal.dart';

class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  String _token = '';
  bool _allowReconnect = true;
  Timer? _reconnectTimer;
  final List<Message> _incoming = [];
  final StreamController<CallSignal> _callSignalController = StreamController<CallSignal>.broadcast();

  bool get connected => _connected;
  List<Message> get pendingIncoming => List.unmodifiable(_incoming);
  Stream<CallSignal> get callSignals => _callSignalController.stream;

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
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          _connected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      _connected = true;
      notifyListeners();
    } catch (_) {
      _connected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_allowReconnect || _token.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_connected && _allowReconnect && _token.isNotEmpty) _doConnect();
    });
  }

  void _onMessage(dynamic data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      if (map['type'] == 'new_message' && map['message'] != null) {
        final msg = Message.fromJson(map['message'] as Map<String, dynamic>);
        _incoming.add(msg);
        notifyListeners();
      } else if (map['type'] == 'call_signal' && map['fromUserId'] != null && map['signal'] != null) {
        _callSignalController.add(CallSignal.fromJson(map));
      }
    } catch (_) {}
  }

  void sendCallSignal(int toUserId, String signal, [Map<String, dynamic>? payload]) {
    if (!_connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'type': 'call_signal',
        'toUserId': toUserId,
        'signal': signal,
        if (payload != null) 'payload': payload,
      }));
    } catch (_) {}
  }

  Message? takeIncomingFor(int peerId) {
    final i = _incoming.indexWhere((m) => m.senderId == peerId);
    if (i < 0) return null;
    return _incoming.removeAt(i);
  }

  void clearPending() {
    _incoming.clear();
    notifyListeners();
  }

  void disconnect() {
    _allowReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _connected = false;
    _incoming.clear();
    notifyListeners();
  }
}
