import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ws_service.dart';
// Note: connectivity_plus нужно добавить в pubspec.yaml
// import 'package:connectivity_plus/connectivity_plus.dart';

/// Виджет для отображения индикатора офлайн режима и переподключения
class OfflineIndicator extends StatefulWidget {
  final Widget child;

  const OfflineIndicator({
    super.key,
    required this.child,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  bool _isOnline = true;
  bool _wsConnected = true;
  StreamSubscription? _wsSubscription;
  // StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _subscribeToWebSocket();
    // После установки connectivity_plus раскомментировать:
    // _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
    //   final isOnline = !results.contains(ConnectivityResult.none);
    //   if (_isOnline != isOnline) {
    //     setState(() {
    //       _isOnline = isOnline;
    //     });
    //   }
    // });
  }

  void _subscribeToWebSocket() {
    try {
      final ws = context.read<WsService>();
      _wsConnected = ws.connected;
      _wsSubscription = ws.onNewMessage.listen((_) {
        // Обновляем состояние при изменении WebSocket
        if (mounted) {
          final newConnected = ws.connected;
          if (_wsConnected != newConnected) {
            setState(() {
              _wsConnected = newConnected;
            });
          }
        }
      });
      // Также слушаем изменения через ChangeNotifier
      ws.addListener(_onWsChange);
    } catch (_) {
      // Если WsService недоступен, игнорируем
    }
  }

  void _onWsChange() {
    if (!mounted) return;
    try {
      final ws = context.read<WsService>();
      final newConnected = ws.connected;
      if (_wsConnected != newConnected) {
        setState(() {
          _wsConnected = newConnected;
        });
      }
    } catch (_) {
      // Игнорируем ошибки
    }
  }

  Future<void> _checkConnectivity() async {
    // После установки connectivity_plus раскомментировать:
    // final results = await Connectivity().checkConnectivity();
    // final isOnline = !results.contains(ConnectivityResult.none);
    // if (mounted) {
    //   setState(() {
    //     _isOnline = isOnline;
    //   });
    // }
    // Пока всегда онлайн
    if (mounted) {
      setState(() {
        _isOnline = true;
      });
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    try {
      context.read<WsService>().removeListener(_onWsChange);
    } catch (_) {
      // Игнорируем ошибки
    }
    // _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOffline = !_isOnline || !_wsConnected;
    final isReconnecting = !_wsConnected && _isOnline;
    
    return Stack(
      children: [
        widget.child,
        if (showOffline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: isReconnecting ? Colors.orange : Colors.red,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isReconnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    isReconnecting ? 'Переподключение...' : 'Офлайн режим',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
