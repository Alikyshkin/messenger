import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';
import '../services/app_sound_service.dart';
import '../services/auth_service.dart';

/// Режим отображения видео: докладчик (большой удалённый), обычный, рядом слева-справа.
enum CallLayout {
  speaker,
  normal,
  sideBySide,
}

/// Экран звонка в стиле Телемост: видео и микрофон выключены по умолчанию,
/// демонстрация экрана, настройки, вкладка участники, переключение вида.
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
  final RTCVideoRenderer _screenRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;
  late Future<void> _renderersFuture;
  String _state = 'init'; // init | calling | ringing | connected | ended
  String? _error;
  final List<Map<String, dynamic>> _pendingCandidates = [];

  /// Видео и микрофон изначально выключены при подключении.
  bool _cameraEnabled = false;
  bool _micEnabled = false;

  /// Демонстрация экрана.
  bool _screenShareEnabled = false;
  MediaStream? _screenStream;
  MediaStreamTrack? _cameraVideoTrack;

  /// Режим раскладки.
  CallLayout _layout = CallLayout.normal;

  /// Панель участников/настроек.
  bool _showPanel = false;
  int _panelTabIndex = 0; // 0 = Участники, 1 = Настройки

  /// Устройства для настроек.
  List<MediaDeviceInfo> _mediaDevices = [];
  String? _selectedVideoDeviceId;
  String? _selectedAudioDeviceId;

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
    await _screenRenderer.initialize();
    if (mounted) setState(() => _renderersInitialized = true);
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _state = 'calling');
    try {
      await _renderersFuture;
      await _getUserMedia();
      _applyInitialMute();
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

  /// После получения потока выключаем видео и микрофон по умолчанию.
  void _applyInitialMute() {
    if (_localStream == null) return;
    for (var t in _localStream!.getVideoTracks()) {
      t.enabled = _cameraEnabled;
    }
    for (var t in _localStream!.getAudioTracks()) {
      t.enabled = _micEnabled;
    }
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) _cameraVideoTrack = videoTracks.first;
  }

  String _mediaErrorMessage(Object e) {
    if (kIsWeb) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('null') || msg.contains('getusermedia') || msg.contains('media')) {
        return 'Видеозвонок в браузере доступен только по HTTPS. Откройте сайт по https:// или используйте приложение на телефоне.';
      }
    }
    if (e.toString().toLowerCase().contains('permission')) {
      return 'Нет доступа к камере или микрофону. Разрешите доступ в настройках.';
    }
    return e.toString();
  }

  Future<void> _getUserMedia({String? videoDeviceId, String? audioDeviceId}) async {
    final Map<String, dynamic> videoConstraint = kIsWeb
        ? {
            'mandatory': {'minWidth': '320', 'minHeight': '240', 'minFrameRate': '15'},
            'facingMode': 'user',
            'optional': [],
          }
        : {
            'facingMode': 'user',
            'width': {'ideal': 640},
            'height': {'ideal': 480},
          };
    final videoConstraintMap = Map<String, dynamic>.from(videoConstraint);
    if (videoDeviceId != null && videoDeviceId.isNotEmpty) {
      if (kIsWeb) {
        videoConstraintMap['optional'] = [
          {'sourceId': videoDeviceId}
        ];
      } else {
        videoConstraintMap['deviceId'] = {'exact': videoDeviceId};
      }
    }
    final Map<String, dynamic> mediaConstraints = {
      'audio': audioDeviceId != null && audioDeviceId.isNotEmpty
          ? {'deviceId': {'exact': audioDeviceId}}
          : true,
      'video': videoConstraintMap,
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      throw Exception(_mediaErrorMessage(e));
    }
    if (_localStream != null) {
      _cameraVideoTrack = _localStream!.getVideoTracks().isNotEmpty
          ? _localStream!.getVideoTracks().first
          : null;
    }
    if (_renderersInitialized && _localStream != null) {
      _localRenderer.srcObject = _localStream;
    }
  }

  void _toggleCamera() {
    if (_localStream == null || _screenShareEnabled) return;
    final videoTracks = _localStream!.getVideoTracks();
    for (final t in videoTracks) {
      t.enabled = !t.enabled;
    }
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  void _toggleMic() {
    if (_localStream == null) return;
    final audioTracks = _localStream!.getAudioTracks();
    for (final t in audioTracks) {
      t.enabled = !t.enabled;
    }
    setState(() => _micEnabled = !_micEnabled);
  }

  Future<void> _toggleScreenShare() async {
    if (_pc == null || _localStream == null) return;
    if (_screenShareEnabled) {
      await _stopScreenShare();
    } else {
      await _startScreenShare();
    }
  }

  Future<void> _startScreenShare() async {
    try {
      final screenStream = await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'video': true,
        'audio': false,
      });
      final screenVideoTracks = screenStream.getVideoTracks();
      if (screenVideoTracks.isEmpty) {
        await screenStream.dispose();
        return;
      }
      final screenTrack = screenVideoTracks.first;
      screenTrack.onEnded = () {
        if (mounted) _stopScreenShare();
      };
      final senders = await _pc!.getSenders();
      RTCRtpSender? videoSender;
      for (final s in senders) {
        if (s.track?.kind == 'video') {
          videoSender = s;
          break;
        }
      }
      if (videoSender != null) {
        await videoSender.replaceTrack(screenTrack);
      }
      _screenStream = screenStream;
      if (_renderersInitialized) _screenRenderer.srcObject = screenStream;
      if (mounted) setState(() => _screenShareEnabled = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось начать демонстрацию: $e')),
        );
      }
    }
  }

  Future<void> _stopScreenShare() async {
    if (_pc == null || !_screenShareEnabled) return;
    final senders = await _pc!.getSenders();
    RTCRtpSender? videoSender;
    for (final s in senders) {
      if (s.track?.kind == 'video') {
        videoSender = s;
        break;
      }
    }
    if (videoSender != null && _cameraVideoTrack != null) {
      await videoSender.replaceTrack(_cameraVideoTrack);
    }
    _screenStream?.getTracks().forEach((t) => t.stop());
    await _screenStream?.dispose();
    _screenStream = null;
    _screenRenderer.srcObject = null;
    if (mounted) setState(() => _screenShareEnabled = false);
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
      if (_state == 'ringing') return;
      try {
        await _renderersFuture;
        await _getUserMedia();
        _applyInitialMute();
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
        if (mounted) {
          AppSoundService.instance.stopRingtone();
          setState(() => _state = 'connected');
        }
      } catch (e) {
        if (mounted) {
          AppSoundService.instance.stopRingtone();
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
      if (mounted) {
        AppSoundService.instance.stopRingtone();
        setState(() => _state = 'connected');
      }
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
    setState(() => _state = 'init');
    try {
      await _renderersFuture;
      await _getUserMedia();
      _applyInitialMute();
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
      if (mounted) {
        AppSoundService.instance.stopRingtone();
        setState(() => _state = 'connected');
      }
    } catch (e) {
      if (mounted) {
        AppSoundService.instance.stopRingtone();
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
    AppSoundService.instance.stopRingtone();
    _signalSub?.cancel();
    if (_screenShareEnabled) await _stopScreenShare();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _screenRenderer.srcObject = null;
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

  Future<void> _loadMediaDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (mounted) setState(() => _mediaDevices = devices);
    } catch (_) {}
  }

  List<MediaDeviceInfo> get _videoInputs =>
      _mediaDevices.where((d) => d.kind == 'videoinput').toList();
  List<MediaDeviceInfo> get _audioInputs =>
      _mediaDevices.where((d) => d.kind == 'audioinput').toList();

  @override
  void dispose() {
    AppSoundService.instance.stopRingtone();
    _signalSub?.cancel();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _screenRenderer.srcObject = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.getTracks().forEach((t) => t.stop());
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _screenRenderer.dispose();
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
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
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

    final myName = context.read<AuthService>().user?.displayName ?? 'Я';
    final isControlsVisible = _state == 'calling' || _state == 'connected';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoLayout(),
            _buildOverlayTitle(),
            if (_state == 'connected' && _renderersInitialized) _buildLocalPreview(isControlsVisible),
            if (_state == 'ringing') _buildIncomingControls(),
            if (isControlsVisible) ...[
              _buildLayoutSwitcher(),
              _buildBottomControls(myName),
            ],
            if (_showPanel && isControlsVisible) _buildPanel(myName),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoLayout() {
    if (!_renderersInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    switch (_layout) {
      case CallLayout.sideBySide:
        return _buildSideBySideLayout();
      case CallLayout.speaker:
      case CallLayout.normal:
        return _buildSpeakerLayout();
    }
  }

  Widget _buildSpeakerLayout() {
    final showRemote = _state == 'connected' && _remoteStream != null;
    final showLocal = _state == 'calling' || (_state == 'connected' && _localStream != null);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showRemote)
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else if (showLocal && !_screenShareEnabled)
          RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else if (showLocal && _screenShareEnabled)
          RTCVideoView(
            _screenRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          )
        else
          Container(color: const Color(0xFF1A1A1A)),
      ],
    );
  }

  Widget _buildSideBySideLayout() {
    final showRemote = _state == 'connected' && _remoteStream != null;
    final showLocal = _localStream != null || _screenShareEnabled;
    return Row(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: showLocal
                ? (_screenShareEnabled
                    ? RTCVideoView(_screenRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
                    : RTCVideoView(_localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
                : const Center(child: Text('Вы', style: TextStyle(color: Colors.white70))),
          ),
        ),
        Container(width: 2, color: Colors.grey.shade800),
        Expanded(
          child: Container(
            color: Colors.black,
            child: showRemote
                ? RTCVideoView(_remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Center(child: Text(widget.peer.displayName, style: const TextStyle(color: Colors.white70))),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayTitle() {
    return Container(
      padding: const EdgeInsets.only(top: 24),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.peer.displayName,
            style: const TextStyle(color: Colors.white, fontSize: 22),
          ),
          Text(
            _state == 'calling'
                ? 'Вызов...'
                : _state == 'ringing'
                    ? 'Входящий звонок'
                    : _state == 'connected'
                        ? 'Видеозвонок'
                        : '...',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalPreview(bool isConnected) {
    return Positioned(
      right: 16,
      top: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 120,
          height: 160,
          child: _screenShareEnabled
              ? RTCVideoView(_screenRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
              : RTCVideoView(_localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Center(
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
    );
  }

  Widget _buildLayoutSwitcher() {
    if (_state != 'connected') return const SizedBox.shrink();
    return Positioned(
      left: 16,
      top: 80,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _layoutButton(CallLayout.speaker, Icons.person, 'Докладчик'),
          const SizedBox(width: 8),
          _layoutButton(CallLayout.normal, Icons.grid_view, 'Обычный'),
          const SizedBox(width: 8),
          _layoutButton(CallLayout.sideBySide, Icons.view_sidebar, 'Рядом'),
        ],
      ),
    );
  }

  Widget _layoutButton(CallLayout layout, IconData icon, String tooltip) {
    final selected = _layout == layout;
    return Material(
      color: selected ? Colors.blue.shade700 : Colors.grey.shade800,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        onPressed: () => setState(() => _layout = layout),
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildBottomControls(String myName) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                onPressed: () => setState(() => _showPanel = !_showPanel),
                icon: Icon(_showPanel ? Icons.keyboard_arrow_down : Icons.people),
                style: IconButton.styleFrom(
                  backgroundColor: _showPanel ? Colors.blue.shade700 : Colors.grey.shade700,
                  foregroundColor: Colors.white,
                ),
                tooltip: _showPanel ? 'Скрыть' : 'Участники и настройки',
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _toggleMic,
                icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                style: IconButton.styleFrom(
                  backgroundColor: _micEnabled ? Colors.grey.shade700 : Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _toggleCamera,
                icon: Icon(_cameraEnabled ? Icons.videocam : Icons.videocam_off),
                style: IconButton.styleFrom(
                  backgroundColor: _cameraEnabled ? Colors.grey.shade700 : Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _screenShareEnabled ? _toggleScreenShare : _toggleScreenShare,
                icon: Icon(_screenShareEnabled ? Icons.stop_screen_share : Icons.screen_share),
                style: IconButton.styleFrom(
                  backgroundColor: _screenShareEnabled ? Colors.orange.shade700 : Colors.grey.shade700,
                  foregroundColor: Colors.white,
                ),
                tooltip: _screenShareEnabled ? 'Остановить демонстрацию' : 'Демонстрация экрана',
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _hangUp,
                icon: const Icon(Icons.call_end),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPanel(String myName) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 100,
      child: Material(
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        color: const Color(0xFF2A2A2A),
        child: DefaultTabController(
          length: 2,
          initialIndex: _panelTabIndex,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                onTap: (i) {
                  setState(() => _panelTabIndex = i);
                  if (i == 1) _loadMediaDevices();
                },
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.blue,
                tabs: const [
                  Tab(text: 'Участники'),
                  Tab(text: 'Настройки'),
                ],
              ),
              SizedBox(
                height: 200,
                child: TabBarView(
                  children: [
                    _buildParticipantsTab(myName),
                    _buildSettingsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantsTab(String myName) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _participantTile(myName, isMe: true),
        const Divider(color: Colors.white24),
        _participantTile(widget.peer.displayName, isMe: false),
      ],
    );
  }

  Widget _participantTile(String name, {required bool isMe}) {
    final micOn = isMe ? _micEnabled : null;
    final videoOn = isMe ? _cameraEnabled : null;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.shade700,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: isMe
          ? Text(
              'Микрофон: ${micOn == true ? "вкл" : "выкл"} · Видео: ${videoOn == true ? "вкл" : "выкл"}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )
          : null,
      trailing: isMe
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(micOn == true ? Icons.mic : Icons.mic_off, color: micOn == true ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Icon(videoOn == true ? Icons.videocam : Icons.videocam_off, color: videoOn == true ? Colors.green : Colors.red, size: 20),
              ],
            )
          : null,
    );
  }

  Widget _buildSettingsTab() {
    _loadMediaDevices();
    final videoInputs = _videoInputs;
    final audioInputs = _audioInputs;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (videoInputs.isNotEmpty) ...[
          const Text('Камера', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedVideoDeviceId ?? videoInputs.first.deviceId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: const Color(0xFF333333),
            style: const TextStyle(color: Colors.white),
            items: videoInputs
                .map((d) => DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(d.label.isNotEmpty ? d.label : 'Камера ${d.deviceId.substring(0, 8)}'),
                    ))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selectedVideoDeviceId = id);
              _getUserMedia(videoDeviceId: id, audioDeviceId: _selectedAudioDeviceId).then((_) {
                if (_pc != null && _localStream != null) {
                  final vTracks = _localStream!.getVideoTracks();
                  final newVideo = vTracks.isNotEmpty ? vTracks.first : null;
                  if (newVideo != null) {
                    _cameraVideoTrack = newVideo;
                    _pc!.getSenders().then((senders) {
                      for (final s in senders) {
                        if (s.track?.kind == 'video' && !_screenShareEnabled) {
                          s.replaceTrack(newVideo);
                          break;
                        }
                      }
                    });
                  }
                }
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (audioInputs.isNotEmpty) ...[
          const Text('Микрофон', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedAudioDeviceId ?? audioInputs.first.deviceId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: const Color(0xFF333333),
            style: const TextStyle(color: Colors.white),
            items: audioInputs
                .map((d) => DropdownMenuItem(
                      value: d.deviceId,
                      child: Text(d.label.isNotEmpty ? d.label : 'Микрофон ${d.deviceId.substring(0, 8)}'),
                    ))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selectedAudioDeviceId = id);
              _getUserMedia(videoDeviceId: _selectedVideoDeviceId, audioDeviceId: id).then((_) {
                if (_pc != null && _localStream != null) {
                  final aTracks = _localStream!.getAudioTracks();
                  final newAudio = aTracks.isNotEmpty ? aTracks.first : null;
                  if (newAudio != null) {
                    _pc!.getSenders().then((senders) {
                      for (final s in senders) {
                        if (s.track?.kind == 'audio') {
                          s.replaceTrack(newAudio);
                          break;
                        }
                      }
                    });
                  }
                }
              });
            },
          ),
        ],
        if (videoInputs.isEmpty && audioInputs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Нет доступных устройств', style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
