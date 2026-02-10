import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';

/// Экран звонка: исходящий (calling), входящий (incoming), в разговоре (connected), завершён (closed).
class CallScreen extends StatefulWidget {
  final User peer;
  final bool isIncoming;
  final CallSignal? initialSignal;

  const CallScreen({
    super.key,
    required this.peer,
    this.isIncoming = false,
    this.initialSignal,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WsService? _ws;
  StreamSubscription<CallSignal>? _signalSub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;
  late Future<void> _renderersFuture;
  String _state = 'init'; // init | calling | ringing | connected | ended
  String? _error;
  final List<Map<String, dynamic>> _pendingCandidates = [];

  @override
  void initState() {
    super.initState();
    _renderersFuture = _initRenderers();
    _ws = context.read<WsService>();
    if (widget.isIncoming && widget.initialSignal != null) {
      _handleSignal(widget.initialSignal!);
    } else if (!widget.isIncoming) {
      _startOutgoingCall();
    }
    _signalSub = _ws!.callSignals.listen((s) {
      if (!mounted || s.fromUserId != widget.peer.id) return;
      _handleSignal(s);
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) setState(() => _renderersInitialized = true);
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _state = 'calling');
    try {
      await _renderersFuture;
      await _getUserMedia();
      _pc = await createPeerConnection(_iceServers, {});
      _setupPeerConnection();
      for (var track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      var offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      _ws!.sendCallSignal(widget.peer.id, 'offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 'ended';
        _error = _mediaErrorMessage(e);
      });
    }
  }

  /// Сообщение для пользователя при ошибке камеры/микрофона (например по HTTP в браузере).
  String _mediaErrorMessage(Object e) {
    if (kIsWeb) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('null') || msg.contains('getusermedia') || msg.contains('media'))
        return 'Видеозвонок в браузере доступен только по HTTPS. Откройте сайт по https:// или используйте приложение на телефоне.';
    }
    if (e.toString().toLowerCase().contains('permission'))
      return 'Нет доступа к камере или микрофону. Разрешите доступ в настройках.';
    return e.toString();
  }

  Future<void> _getUserMedia() async {
    if (kIsWeb) {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {
            'mandatory': {
              'minWidth': '320',
              'minHeight': '240',
              'minFrameRate': '15',
            },
            'facingMode': 'user',
            'optional': [],
          },
        });
      } catch (e) {
        throw Exception(_mediaErrorMessage(e));
      }
    } else {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'mandatory': {
            'minWidth': '320',
            'minHeight': '240',
            'minFrameRate': '15',
          },
          'facingMode': 'user',
          'optional': [],
        },
      });
    }
    if (_renderersInitialized && _localStream != null) _localRenderer.srcObject = _localStream;
  }

  void _setupPeerConnection() {
    _pc!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) return;
      _ws!.sendCallSignal(widget.peer.id, 'ice', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        if (_renderersInitialized) _remoteRenderer.srcObject = _remoteStream;
        if (mounted) setState(() {});
      }
    };
    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (mounted) _endCall();
      }
    };
  }

  void _handleSignal(CallSignal s) async {
    if (s.signal == 'hangup' || s.signal == 'reject') {
      if (mounted) _endCall();
      return;
    }
    if (s.signal == 'offer' && s.payload != null) {
      if (_state == 'init') {
        setState(() => _state = 'ringing');
        return;
      }
      if (_state == 'ringing') return; // already showing incoming
      try {
        await _renderersFuture;
        await _getUserMedia();
        _pc = await createPeerConnection(_iceServers, {});
        _setupPeerConnection();
        for (var track in _localStream!.getTracks()) {
          await _pc!.addTrack(track, _localStream!);
        }
        var desc = RTCSessionDescription(
          s.payload!['sdp'] as String,
          s.payload!['type'] as String,
        );
        await _pc!.setRemoteDescription(desc);
        var answer = await _pc!.createAnswer({});
        await _pc!.setLocalDescription(answer);
        _ws!.sendCallSignal(widget.peer.id, 'answer', {
          'sdp': answer.sdp,
          'type': answer.type,
        });
        if (mounted) setState(() => _state = 'connected');
      } catch (e) {
        if (mounted) {
          setState(() {
            _state = 'ended';
            _error = _mediaErrorMessage(e);
          });
        }
      }
      return;
    }
    if (s.signal == 'answer' && s.payload != null) {
      var desc = RTCSessionDescription(
        s.payload!['sdp'] as String,
        s.payload!['type'] as String,
      );
      await _pc?.setRemoteDescription(desc);
      if (mounted) setState(() => _state = 'connected');
      return;
    }
    if (s.signal == 'ice' && s.payload != null) {
      if (_pc != null) {
        var c = s.payload!;
        var candidate = RTCIceCandidate(
          c['candidate'] as String,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        );
        await _pc!.addCandidate(candidate);
      } else {
        _pendingCandidates.add(s.payload!);
      }
    }
  }

  Future<void> _acceptCall() async {
    final offerPayload = widget.initialSignal?.payload;
    if (offerPayload == null) return;
    setState(() => _state = 'init'); // allow _handleSignal to run
    try {
      await _renderersFuture;
      await _getUserMedia();
      _pc = await createPeerConnection(_iceServers, {});
      _setupPeerConnection();
      for (var track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      var desc = RTCSessionDescription(
        offerPayload['sdp'] as String,
        offerPayload['type'] as String,
      );
      await _pc!.setRemoteDescription(desc);
      for (var c in _pendingCandidates) {
        await _pc!.addCandidate(RTCIceCandidate(
          c['candidate'] as String,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        ));
      }
      _pendingCandidates.clear();
      var answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);
      _ws!.sendCallSignal(widget.peer.id, 'answer', {
        'sdp': answer.sdp,
        'type': answer.type,
      });
      if (mounted) setState(() => _state = 'connected');
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = 'ended';
          _error = _mediaErrorMessage(e);
        });
      }
    }
  }

  void _rejectCall() {
    _ws!.sendCallSignal(widget.peer.id, 'reject');
    _endCall();
  }

  void _hangUp() {
    _ws!.sendCallSignal(widget.peer.id, 'hangup');
    _endCall();
  }

  Future<void> _endCall() async {
    _signalSub?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localStream?.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    if (mounted) {
      setState(() => _state = 'ended');
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _signalSub?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == 'ended') {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_state == 'connected' && _renderersInitialized)
              RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else if (_state == 'calling' && _renderersInitialized)
              RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            Container(
              color: _state == 'connected' ? Colors.transparent : const Color(0xFF1A1A1A),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  Text(
                    widget.peer.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  Text(
                    _state == 'calling'
                        ? 'Вызов...'
                        : _state == 'ringing'
                            ? 'Входящий звонок'
                            : _state == 'connected'
                                ? 'Видеозвонок'
                                : '...',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (_state != 'connected' && _state != 'calling') const Spacer(),
                ],
              ),
            ),
            if (_state == 'connected' && _renderersInitialized)
              Positioned(
                right: 16,
                top: 80,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 120,
                    height: 160,
                    child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              ),
            if (_state == 'ringing')
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filled(
                      onPressed: _rejectCall,
                      icon: const Icon(Icons.call_end),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 32),
                    IconButton.filled(
                      onPressed: _acceptCall,
                      icon: const Icon(Icons.videocam),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            else if (_state == 'calling' || _state == 'connected')
              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: Center(
                  child: IconButton.filled(
                    onPressed: _hangUp,
                    icon: const Icon(Icons.call_end),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(24),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
