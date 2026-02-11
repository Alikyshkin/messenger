import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';
import '../services/auth_service.dart';
import '../services/app_sound_service.dart';
import '../services/api.dart';
import '../utils/app_page_route.dart';
import '../utils/page_visibility.dart';
import '../screens/call_screen.dart';

/// Слушает входящие звонки (offer) и открывает экран звонка. Проигрывает рингтон,
/// при неактивной вкладке показывает браузерное уведомление и пытается перевести фокус.
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
    _sub = ws.callSignals.listen((signal) async {
      if (!mounted || signal.signal != 'offer') return;
      
      // Загружаем информацию о пользователе
      User peer;
      try {
        final api = Api(auth.token);
        peer = await api.getUserProfile(signal.fromUserId);
      } catch (e) {
        // Если не удалось загрузить, используем заглушку
        peer = User(
          id: signal.fromUserId,
          username: '',
          displayName: 'Пользователь #${signal.fromUserId}',
        );
      }

      AppSoundService.instance.playRingtone();

      if (!isPageVisible) {
        await requestNotificationPermission();
        final isVideoCall = signal.isVideoCall ?? true;
        await showPageNotification(
          title: isVideoCall ? 'Входящий видеозвонок' : 'Входящий звонок',
          body: peer.displayName,
        );
        await focusWindow();
      }

      if (!mounted) return;
      // Определяем тип звонка из сигнала (по умолчанию видеозвонок для совместимости)
      final isVideoCall = signal.isVideoCall ?? true;
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => CallScreen(
            peer: peer,
            isIncoming: true,
            initialSignal: signal,
            isVideoCall: isVideoCall,
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
