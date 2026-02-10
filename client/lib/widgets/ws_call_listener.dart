import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';
import '../services/auth_service.dart';
import '../screens/call_screen.dart';

/// Слушает входящие звонки (offer) и открывает экран звонка.
class WsCallListener extends StatefulWidget {
  final Widget child;

  const WsCallListener({super.key, required this.child});

  @override
  State<WsCallListener> createState() => _WsCallListenerState();
}

class _WsCallListenerState extends State<WsCallListener> {
  StreamSubscription<CallSignal>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    if (!mounted) return;
    final ws = context.read<WsService>();
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    _sub?.cancel();
    _sub = ws.callSignals.listen((signal) {
      if (!mounted || signal.signal != 'offer') return;
      final peer = User(
        id: signal.fromUserId,
        username: '',
        displayName: 'Пользователь #${signal.fromUserId}',
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            peer: peer,
            isIncoming: true,
            initialSignal: signal,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
