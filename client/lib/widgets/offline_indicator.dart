import 'dart:async';
import 'package:flutter/material.dart';
// Note: connectivity_plus нужно добавить в pubspec.yaml
// import 'package:connectivity_plus/connectivity_plus.dart';

/// Виджет для отображения индикатора офлайн режима
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
  // StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
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
    // _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isOnline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.orange,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Офлайн режим',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
