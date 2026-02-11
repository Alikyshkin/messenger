import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';
import '../services/app_sound_service.dart';
import '../services/auth_service.dart';
import '../services/api.dart';

/// Участник группового звонка с его PeerConnection и потоком
class _GroupCallParticipant {
  final User user;
  RTCPeerConnection? peerConnection;
  MediaStream? remoteStream;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool rendererInitialized = false;
  String state = 'connecting'; // connecting | connected | disconnected | failed
  bool hasVideo = false;
  bool hasAudio = false;
  final List<Map<String, dynamic>> pendingCandidates =
      []; // Отложенные ICE кандидаты
  bool offerReceived = false; // Флаг, что offer уже был обработан

  _GroupCallParticipant(this.user);

  void dispose() {
    peerConnection?.close();
    remoteStream?.dispose();
    if (rendererInitialized) {
      renderer.dispose();
    }
    pendingCandidates.clear();
  }
}

/// Экран группового видеозвонка с поддержкой нескольких участников (mesh topology)
class GroupCallScreen extends StatefulWidget {
  final Group group;
  final bool isIncoming;
  final CallSignal? initialSignal;

  const GroupCallScreen({
    super.key,
    required this.group,
    this.isIncoming = false,
    this.initialSignal,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WsService? _ws;
  StreamSubscription<CallSignal>? _signalSub;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;

  // Участники группового звонка (кроме текущего пользователя)
  final Map<int, _GroupCallParticipant> _participants = {};

  String _state = 'init'; // init | calling | ringing | connected | ended
  String? _error;

  bool _cameraEnabled = true;
  bool _micEnabled = true;
  bool _isFrontCamera = true;

  int? _myUserId;
  List<GroupMember>? _groupMembers;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCall());
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    setState(() => _localRendererInitialized = true);
  }

  Future<void> _initCall() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      Navigator.of(context).pop();
      return;
    }

    _myUserId = auth.user?.id;
    _ws = context.read<WsService>();

    // Загружаем актуальный список участников группы
    try {
      final api = Api(auth.token);
      final group = await api.getGroup(widget.group.id);
      if (!mounted) return;
      _groupMembers = group.members;

      // Инициализируем участников (исключая себя)
      if (_groupMembers != null) {
        for (final member in _groupMembers!) {
          if (member.id != _myUserId) {
            final participant = _GroupCallParticipant(
              User(
                id: member.id,
                username: member.username,
                displayName: member.displayName,
                avatarUrl: member.avatarUrl,
              ),
            );
            _participants[member.id] = participant;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки участников группы';
        _state = 'ended';
      });
      return;
    }

    _signalSub = _ws!.callSignals.listen(_handleSignal);

    if (widget.isIncoming) {
      if (widget.initialSignal != null &&
          widget.initialSignal!.signal == 'offer') {
        AppSoundService.instance.playRingtone();
        setState(() => _state = 'ringing');
      }
    } else {
      _startOutgoingCall();
    }
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _state = 'calling');
    try {
      // Получаем медиа только один раз
      if (_localStream == null) {
        await _getUserMedia();
        _applyInitialMute();
      }
      
      // Инициализируем renderers для всех участников
      for (final participant in _participants.values) {
        if (!participant.rendererInitialized) {
          await participant.renderer.initialize();
          participant.rendererInitialized = true;
        }
      }
      
      // Создаем PeerConnection для каждого участника
      for (final participant in _participants.values) {
        await _createPeerConnectionForParticipant(participant);
      }
      
      // Отправляем сигнал группового звонка всем участникам
      _ws!.sendGroupCallSignal(widget.group.id, 'offer', null, true);
      
      setState(() => _state = 'connected');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 'ended';
        _error = _mediaErrorMessage(e);
      });
    }
  }

  Future<void> _getUserMedia() async {
    final Map<String, dynamic> videoConstraint = kIsWeb
        ? {
            'mandatory': {
              'minWidth': '640',
              'minHeight': '480',
              'minFrameRate': '24',
            },
            'facingMode': _isFrontCamera ? 'user' : 'environment',
          }
        : {
            'facingMode': _isFrontCamera ? 'user' : 'environment',
            'width': {'ideal': 1280, 'min': 640},
            'height': {'ideal': 720, 'min': 480},
            'frameRate': {'ideal': 30, 'min': 24},
          };

    final mediaConstraints = {'audio': true, 'video': videoConstraint};

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (_localRendererInitialized && _localStream != null) {
      _localRenderer.srcObject = _localStream;
    }
  }

  void _applyInitialMute() {
    if (_localStream == null) return;
    for (var t in _localStream!.getVideoTracks()) {
      t.enabled = _cameraEnabled;
    }
    for (var t in _localStream!.getAudioTracks()) {
      t.enabled = _micEnabled;
    }
  }

  Future<void> _createPeerConnectionForParticipant(
    _GroupCallParticipant participant,
  ) async {
    try {
      final pc = await createPeerConnection(_iceServers, {});
      participant.peerConnection = pc;

      // Добавляем локальные треки
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await pc.addTrack(track, _localStream!);
        }
      }

      // Настраиваем обработчики
      _setupParticipantPeerConnection(participant);

      // Создаем offer
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await pc.setLocalDescription(offer);

      // Отправляем offer
      _ws!.sendCallSignal(
        participant.user.id,
        'offer',
        {'sdp': offer.sdp, 'type': offer.type},
        true,
        widget.group.id,
      );
    } catch (e) {
      print(
        'Error creating PeerConnection for participant ${participant.user.id}: $e',
      );
      if (mounted) {
        setState(() {
          participant.state = 'failed';
        });
      }
    }
  }

  Future<void> _handleSignal(CallSignal signal) async {
    // Фильтруем сигналы только для этой группы
    if (signal.groupId != null && signal.groupId != widget.group.id) return;

    // Игнорируем сигналы не от участников группы
    if (!_participants.containsKey(signal.fromUserId)) return;

    final participant = _participants[signal.fromUserId]!;

    if (signal.signal == 'hangup' || signal.signal == 'reject') {
      if (mounted) {
        setState(() {
          participant.state = 'disconnected';
        });
      }
      // Закрываем PeerConnection при отключении
      participant.peerConnection?.close();
      participant.peerConnection = null;
      return;
    }

    if (signal.signal == 'offer' && signal.payload != null) {
      // Предотвращаем обработку дублирующих offer
      if (participant.offerReceived && participant.peerConnection != null) {
        print('Duplicate offer received from ${signal.fromUserId}, ignoring');
        return;
      }
      participant.offerReceived = true;

      try {
        // Инициализируем renderer для участника
        if (!participant.rendererInitialized) {
          await participant.renderer.initialize();
          participant.rendererInitialized = true;
        }

        // Создаем PeerConnection если его еще нет
        if (participant.peerConnection == null) {
          // Получаем медиа только если еще не получили
          if (_localStream == null) {
            await _getUserMedia();
            _applyInitialMute();
          }

          final pc = await createPeerConnection(_iceServers, {});
          participant.peerConnection = pc;

          if (_localStream != null) {
            for (var track in _localStream!.getTracks()) {
              await pc.addTrack(track, _localStream!);
            }
          }

          _setupParticipantPeerConnection(participant);
        }

        final pc = participant.peerConnection!;
        final desc = RTCSessionDescription(
          signal.payload!['sdp'] as String,
          signal.payload!['type'] as String,
        );
        await pc.setRemoteDescription(desc);

        // Обрабатываем отложенные ICE кандидаты перед созданием answer
        for (var c in participant.pendingCandidates) {
          try {
            await pc.addCandidate(
              RTCIceCandidate(
                c['candidate'] as String,
                c['sdpMid'] as String?,
                c['sdpMLineIndex'] as int?,
              ),
            );
          } catch (e) {
            print('Error adding pending candidate: $e');
          }
        }
        participant.pendingCandidates.clear();

        final answer = await pc.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        });
        await pc.setLocalDescription(answer);

        _ws!.sendCallSignal(
          signal.fromUserId,
          'answer',
          {'sdp': answer.sdp, 'type': answer.type},
          true,
          widget.group.id,
        );

        AppSoundService.instance.stopRingtone();
        if (mounted) {
          setState(() {
            _state = 'connected';
            participant.state = 'connected';
          });
        }
      } catch (e) {
        print('Error handling offer signal: $e');
        if (mounted) {
          setState(() {
            participant.state = 'failed';
          });
        }
      }
    } else if (signal.signal == 'answer' &&
        signal.payload != null &&
        participant.peerConnection != null) {
      try {
        final desc = RTCSessionDescription(
          signal.payload!['sdp'] as String,
          signal.payload!['type'] as String,
        );
        await participant.peerConnection!.setRemoteDescription(desc);
        if (mounted) {
          setState(() {
            participant.state = 'connected';
          });
        }
      } catch (e) {
        print('Error handling answer signal: $e');
        if (mounted) {
          setState(() {
            participant.state = 'failed';
          });
        }
      }
    } else if (signal.signal == 'ice' && signal.payload != null) {
      // Если PeerConnection еще не создан, сохраняем кандидата
      if (participant.peerConnection == null) {
        participant.pendingCandidates.add(signal.payload!);
        return;
      }

      try {
        await participant.peerConnection!.addCandidate(
          RTCIceCandidate(
            signal.payload!['candidate'] as String,
            signal.payload!['sdpMid'] as String?,
            signal.payload!['sdpMLineIndex'] as int?,
          ),
        );
      } catch (e) {
        print('Error adding ICE candidate: $e');
      }
    }
  }

  void _setupParticipantPeerConnection(_GroupCallParticipant participant) {
    final pc = participant.peerConnection!;

    pc.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) return;
      _ws!.sendCallSignal(
        participant.user.id,
        'ice',
        {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        true,
        widget.group.id,
      );
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        participant.remoteStream = event.streams.first;
        participant.hasVideo = event.track.kind == 'video';
        participant.hasAudio = event.track.kind == 'audio';
        if (participant.rendererInitialized) {
          participant.renderer.srcObject = participant.remoteStream;
        }
        if (mounted) {
          setState(() {
            participant.state = 'connected';
          });
        }
      }
    };

    pc.onConnectionState = (state) {
      print('Participant ${participant.user.id} connection state: $state');
      if (mounted) {
        setState(() {});
      }
    };

    pc.onIceConnectionState = (state) {
      print('Participant ${participant.user.id} ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (mounted) {
          setState(() {
            participant.state = 'disconnected';
          });
        }
        // Проверяем, остались ли подключенные участники
        _checkIfCallShouldEnd();
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (mounted) {
          setState(() {
            participant.state = 'connected';
          });
        }
      }
    };
  }

  void _checkIfCallShouldEnd() {
    final connectedCount = _participants.values
        .where((p) => p.state == 'connected')
        .length;
    // Если нет подключенных участников и мы не в процессе звонка, можно завершить
    if (connectedCount == 0 &&
        _state == 'connected' &&
        _participants.isNotEmpty) {
      // Не завершаем автоматически, просто обновляем состояние
      if (mounted) {
        setState(() {
          _state = 'calling'; // Возвращаемся в состояние вызова
        });
      }
    }
  }

  void _acceptCall() async {
    AppSoundService.instance.stopRingtone();
    setState(() => _state = 'connected');
    
    try {
      // Получаем медиа только если еще не получили
      if (_localStream == null) {
        await _getUserMedia();
        _applyInitialMute();
      }
      
      // Инициализируем renderers для всех участников
      for (final participant in _participants.values) {
        if (!participant.rendererInitialized) {
          await participant.renderer.initialize();
          participant.rendererInitialized = true;
        }
      }
      
      // Создаем PeerConnection для каждого участника
      for (final participant in _participants.values) {
        await _createPeerConnectionForParticipant(participant);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mediaErrorMessage(e);
        _state = 'ended';
      });
    }
  }

  void _rejectCall() {
    _ws!.sendGroupCallSignal(widget.group.id, 'reject', null, true);
    _endCall();
  }

  void _endCall() {
    _ws!.sendGroupCallSignal(widget.group.id, 'hangup', null, true);
    // Также отправляем hangup каждому участнику индивидуально
    for (final participant in _participants.values) {
      if (participant.peerConnection != null) {
        _ws!.sendCallSignal(
          participant.user.id,
          'hangup',
          null,
          true,
          widget.group.id,
        );
      }
    }
    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanup() {
    AppSoundService.instance.stopRingtone();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    if (_localRendererInitialized) {
      _localRenderer.srcObject = null;
      _localRenderer.dispose();
    }
    for (final participant in _participants.values) {
      participant.dispose();
    }
    _participants.clear();
    _signalSub?.cancel();
  }

  void _toggleCamera() {
    if (_localStream == null) return;
    setState(() => _cameraEnabled = !_cameraEnabled);
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = _cameraEnabled;
    }
  }

  void _toggleMic() {
    if (_localStream == null) return;
    setState(() => _micEnabled = !_micEnabled);
    for (var track in _localStream!.getAudioTracks()) {
      track.enabled = _micEnabled;
    }
  }

  String _mediaErrorMessage(dynamic e) {
    if (e.toString().contains('Permission denied') ||
        e.toString().contains('NotAllowedError')) {
      return 'Нет доступа к камере/микрофону';
    }
    if (e.toString().contains('NotFoundError') ||
        e.toString().contains('DevicesNotFoundError')) {
      return 'Камера/микрофон не найдены';
    }
    return e.toString();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == 'ended' && _error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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

    final connectedParticipants = _participants.values
        .where((p) => p.state == 'connected')
        .toList();
    final connectingParticipants = _participants.values
        .where((p) => p.state == 'connecting')
        .toList();
    final totalParticipants = _participants.length + 1; // +1 для себя

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Видео сетка участников - показываем даже если есть подключающиеся
            if (_state == 'connected' || _state == 'calling')
              if (connectedParticipants.isNotEmpty || connectingParticipants.isNotEmpty || _localRendererInitialized)
                _buildVideoGrid(connectedParticipants, connectingParticipants)
              else
                _buildCallingView()
            else if (_state == 'ringing')
              _buildRingingView()
            else if (_state == 'calling')
              _buildCallingView()
            else
              _buildWaitingView(),

            // Заголовок с названием группы
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      widget.group.name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '($totalParticipants)',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Кнопки управления
            if (_state == 'ringing')
              _buildIncomingControls()
            else if (_state == 'connected' || _state == 'calling')
              _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid(List<_GroupCallParticipant> connectedParticipants, List<_GroupCallParticipant> connectingParticipants) {
    // Добавляем локальное видео в начало списка
    // Показываем подключенных и подключающихся участников
    final allParticipants = [
      if (_localRendererInitialized && _localStream != null)
        null, // null означает локальное видео
      ...connectedParticipants,
      ...connectingParticipants, // Показываем подключающихся участников
    ];

    final count = allParticipants.length;
    if (count == 0) return _buildWaitingView();

    // Определяем количество колонок в зависимости от количества участников
    int columns;
    if (count <= 2)
      columns = 1;
    else if (count <= 4)
      columns = 2;
    else if (count <= 9)
      columns = 3;
    else
      columns = 4;

    // rows вычисляется для информации, но не используется напрямую
    // GridView автоматически вычисляет количество строк

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (allParticipants[index] == null) {
          // Локальное видео
          return Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RTCVideoView(
                    _localRenderer,
                    mirror: _isFrontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Вы',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          final participant = allParticipants[index] as _GroupCallParticipant;
          return Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (participant.rendererInitialized &&
                      participant.remoteStream != null &&
                      participant.hasVideo)
                    RTCVideoView(
                      participant.renderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    Container(
                      color: Colors.grey.shade900,
                      child: Center(
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.blue.shade700,
                          backgroundImage: participant.user.avatarUrl != null
                              ? NetworkImage(participant.user.avatarUrl!)
                              : null,
                          child: participant.user.avatarUrl == null
                              ? Text(
                                  participant.user.displayName.isNotEmpty
                                      ? participant.user.displayName[0]
                                            .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (participant.state == 'connecting')
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blue,
                              ),
                            )
                          else if (!participant.hasAudio)
                            const Icon(
                              Icons.mic_off,
                              color: Colors.red,
                              size: 12,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            participant.user.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Индикатор состояния подключения
                  if (participant.state == 'connecting')
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Подключение...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildRingingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.blue.shade700,
            backgroundImage: widget.group.avatarUrl != null
                ? NetworkImage(widget.group.avatarUrl!)
                : null,
            child: widget.group.avatarUrl == null
                ? Text(
                    widget.group.name.isNotEmpty
                        ? widget.group.name[0].toUpperCase()
                        : 'G',
                    style: const TextStyle(color: Colors.white, fontSize: 48),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Text(
            widget.group.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Входящий групповой видеозвонок',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCallingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.blue.shade700,
            backgroundImage: widget.group.avatarUrl != null
                ? NetworkImage(widget.group.avatarUrl!)
                : null,
            child: widget.group.avatarUrl == null
                ? Text(
                    widget.group.name.isNotEmpty
                        ? widget.group.name[0].toUpperCase()
                        : 'G',
                    style: const TextStyle(color: Colors.white, fontSize: 48),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Text(
            widget.group.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Вызов...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 24),
          Text(
            widget.group.name,
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
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

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filled(
            onPressed: _toggleMic,
            icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
            style: IconButton.styleFrom(
              backgroundColor: _micEnabled
                  ? Colors.grey.shade700
                  : Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: _toggleCamera,
            icon: Icon(_cameraEnabled ? Icons.videocam : Icons.videocam_off),
            style: IconButton.styleFrom(
              backgroundColor: _cameraEnabled
                  ? Colors.grey.shade700
                  : Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: _endCall,
            icon: const Icon(Icons.call_end),
            style: IconButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
