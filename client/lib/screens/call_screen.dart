import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/call_signal.dart';
import '../services/ws_service.dart';
import '../services/app_sound_service.dart';
import '../services/auth_service.dart';
import '../utils/webrtc_constants.dart';
import '../utils/media_utils.dart';
import '../utils/call_network_quality.dart';
import '../widgets/call_action_button.dart';
import '../widgets/call_control_button.dart';
import '../widgets/call_layout_button.dart';
import '../services/call_minimized_service.dart';
import '../services/app_update_service.dart';
import '../utils/page_visibility.dart';
import '../utils/user_action_logger.dart';

/// Режим отображения видео: докладчик (большой удалённый), обычный, рядом слева-справа.
enum CallLayout { speaker, normal, sideBySide }

/// Экран звонка в стиле Телемост: видео и микрофон выключены по умолчанию,
/// демонстрация экрана, настройки, вкладка участники, переключение вида.
class CallScreen extends StatefulWidget {
  final User peer;
  final bool isIncoming;
  final CallSignal? initialSignal;
  final bool isVideoCall; // true для видеозвонка, false для голосового

  const CallScreen({
    super.key,
    required this.peer,
    this.isIncoming = false,
    this.initialSignal,
    this.isVideoCall = true, // По умолчанию видеозвонок
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
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
  String _state =
      'init'; // init | calling | ringing | connected | ended | peer_disconnected
  String? _error;
  final List<Map<String, dynamic>> _pendingCandidates = [];
  bool _offerReceived = false; // Флаг для защиты от дублирующих offer
  bool _isConnecting = false; // Флаг процесса подключения

  /// Видео и микрофон включены по умолчанию для видеозвонка.
  /// Для голосового звонка камера выключена.
  bool _cameraEnabled = true;
  bool _micEnabled = true;

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

  /// Переключение между передней и задней камерой.
  bool _isFrontCamera = true;

  /// Качество сети (обновляется по getStats).
  NetworkQuality _networkQuality = NetworkQuality.unknown;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    AppSoundService.instance.setInCall(true);
    if (!widget.isIncoming) {
      AppSoundService.instance.stopRingtone();
    }
    _renderersFuture = _initRenderers();
    _ws = context.read<WsService>();
    context.read<CallMinimizedService>().registerActiveCall(
      widget.peer,
      widget.isVideoCall,
    );

    // Проверяем, не идет ли уже звонок с этим пользователем (при разворачивании из минимизации)
    final minimizedService = context.read<CallMinimizedService>();
    if (minimizedService.isMinimized &&
        minimizedService.peer?.id == widget.peer.id &&
        !widget.isIncoming) {
      // Если звонок был минимизирован и мы разворачиваем его,
      // нужно восстановить состояние, но так как экран был закрыт,
      // состояние потеряно. Поэтому просто начинаем новый звонок.
      // Для полного решения нужно использовать Overlay или другой механизм.
      minimizedService.expandCall();
    }

    if (widget.isIncoming && widget.initialSignal != null) {
      _handleSignal(widget.initialSignal!);
    } else if (!widget.isIncoming) {
      _startOutgoingCall();
    }
    _signalSub = _ws!.callSignals.listen((s) {
      if (!mounted || s.fromUserId != widget.peer.id) {
        return;
      }
      _handleSignal(s);
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _screenRenderer.initialize();
    if (mounted) {
      setState(() => _renderersInitialized = true);
    }
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _state = 'calling');
    try {
      await _renderersFuture;

      // Получаем медиа только если еще не получили
      if (_localStream == null) {
        await _getUserMedia(videoDeviceId: null, audioDeviceId: null);
        _applyInitialMute();
      }

      _pc = await createPeerConnection(WebRTCConstants.iceServers, {});
      _setupPeerConnection();
      for (var track in _localStream!.getTracks()) {
        debugPrint(
          'Adding track to PeerConnection (initiate): ${track.kind}, enabled: ${track.enabled}',
        );
        await _pc!.addTrack(track, _localStream!);
      }
      // Для голосовых звонков убеждаемся, что аудио треки включены
      if (!widget.isVideoCall) {
        for (var track in _localStream!.getAudioTracks()) {
          if (!track.enabled) {
            track.enabled = true;
            debugPrint('Enabled local audio track for voice call');
          }
        }
      }
      var offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideoCall,
      });
      await _pc!.setLocalDescription(offer);
      _ws!.sendCallSignal(widget.peer.id, 'offer', {
        'sdp': offer.sdp,
        'type': offer.type,
      }, widget.isVideoCall);

      // Устанавливаем флаг подключения после отправки offer
      setState(() => _isConnecting = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 'ended';
        _error = MediaUtils.getMediaErrorMessage(e);
        _isConnecting = false;
      });
    }
  }

  /// Применяем состояние видео и микрофона к трекам.
  void _applyInitialMute() {
    _applyInitialMuteForCallType(widget.isVideoCall);
  }

  /// Применяем состояние видео и микрофона к трекам с учетом типа звонка.
  void _applyInitialMuteForCallType(bool isVideoCall) {
    if (_localStream == null) {
      return;
    }
    // Для голосового звонка камера выключена
    if (!isVideoCall) {
      _cameraEnabled = false;
    }
    for (var t in _localStream!.getVideoTracks()) {
      t.enabled = _cameraEnabled && isVideoCall;
    }
    for (var t in _localStream!.getAudioTracks()) {
      t.enabled = _micEnabled;
    }
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      _cameraVideoTrack = videoTracks.first;
    }
  }

  /// Очистка потоков и PeerConnection при переподключении
  Future<void> _cleanupForReconnect() async {
    // Останавливаем все треки локального потока
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    // Очищаем удаленный поток
    _remoteStream = null;
    _remoteRenderer.srcObject = null;

    // Закрываем PeerConnection
    await _pc?.close();
    _pc = null;

    // Очищаем отложенные кандидаты
    _pendingCandidates.clear();
  }

  Future<void> _getUserMedia({
    String? videoDeviceId,
    String? audioDeviceId,
    bool? isVideoCall,
  }) async {
    MediaUtils.ensureCanUseMedia();
    final callType = isVideoCall ?? widget.isVideoCall;
    final Map<String, dynamic> mediaConstraints = {
      'audio': audioDeviceId != null && audioDeviceId.isNotEmpty
          ? {
              'deviceId': {'exact': audioDeviceId},
            }
          : true,
      'video': callType
          ? MediaUtils.buildVideoConstraints(
              isFrontCamera: _isFrontCamera,
              videoDeviceId: videoDeviceId,
            )
          : false,
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
    } catch (e) {
      throw Exception(MediaUtils.getMediaErrorMessage(e));
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
    logUserAction('call_toggle_camera', {'enabled': !_cameraEnabled});
    if (_localStream == null || _screenShareEnabled) {
      return;
    }
    final videoTracks = _localStream!.getVideoTracks();
    for (final t in videoTracks) {
      t.enabled = !t.enabled;
    }
    setState(() => _cameraEnabled = !_cameraEnabled);
  }

  /// Переключение между передней и задней камерой.
  Future<void> _switchCamera() async {
    logUserAction('call_switch_camera');
    if (_localStream == null || _screenShareEnabled || _pc == null) {
      return;
    }
    _isFrontCamera = !_isFrontCamera;
    try {
      // Получаем новое видео с другой камеры
      await _getUserMedia(
        videoDeviceId: null, // Будет использован facingMode
        audioDeviceId: _selectedAudioDeviceId,
      );
      // Обновляем трек в PeerConnection
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        _cameraVideoTrack = videoTracks.first;
        final senders = await _pc!.getSenders();
        for (final s in senders) {
          if (s.track?.kind == 'video' && !_screenShareEnabled) {
            await s.replaceTrack(_cameraVideoTrack);
            break;
          }
        }
      }
      if (_renderersInitialized && _localStream != null) {
        _localRenderer.srcObject = _localStream;
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Возвращаемся к предыдущей камере при ошибке
      _isFrontCamera = !_isFrontCamera;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось переключить камеру: $e')),
        );
      }
    }
  }

  void _toggleMic() {
    logUserAction('call_toggle_mic', {'enabled': !_micEnabled});
    if (_localStream == null) {
      return;
    }
    final audioTracks = _localStream!.getAudioTracks();
    for (final t in audioTracks) {
      t.enabled = !t.enabled;
    }
    setState(() => _micEnabled = !_micEnabled);
  }

  Future<void> _toggleScreenShare() async {
    logUserAction('call_toggle_screen_share', {
      'enabled': !_screenShareEnabled,
    });
    if (_pc == null || _localStream == null) {
      return;
    }
    if (_screenShareEnabled) {
      await _stopScreenShare();
    } else {
      await _startScreenShare();
    }
  }

  Future<void> _startScreenShare() async {
    try {
      final screenStream = await navigator.mediaDevices.getDisplayMedia(
        <String, dynamic>{'video': true, 'audio': false},
      );
      final screenVideoTracks = screenStream.getVideoTracks();
      if (screenVideoTracks.isEmpty) {
        await screenStream.dispose();
        return;
      }
      final screenTrack = screenVideoTracks.first;
      screenTrack.onEnded = () {
        if (mounted) {
          _stopScreenShare();
        }
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
      if (_renderersInitialized) {
        _screenRenderer.srcObject = screenStream;
      }
      if (mounted) {
        setState(() => _screenShareEnabled = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось начать демонстрацию: $e')),
        );
      }
    }
  }

  Future<void> _stopScreenShare() async {
    if (_pc == null || !_screenShareEnabled) {
      return;
    }
    final senders = await _pc!.getSenders();
    RTCRtpSender? videoSender;
    for (final s in senders) {
      if (s.track?.kind == 'video') {
        videoSender = s;
        break;
      }
    }
    // Если камера была отключена, нужно включить её снова или использовать существующий трек
    if (videoSender != null) {
      if (_cameraVideoTrack != null) {
        await videoSender.replaceTrack(_cameraVideoTrack);
      } else if (_localStream != null) {
        // Если трек камеры потерян, получаем новый
        final videoTracks = _localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          _cameraVideoTrack = videoTracks.first;
          await videoSender.replaceTrack(_cameraVideoTrack);
        }
      }
    }
    _screenStream?.getTracks().forEach((t) => t.stop());
    await _screenStream?.dispose();
    _screenStream = null;
    _screenRenderer.srcObject = null;
    if (mounted) {
      setState(() => _screenShareEnabled = false);
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _pc == null || _state != 'connected') return;
      try {
        final reports = await _pc!.getStats();
        final q = CallNetworkQuality.fromStats(reports);
        if (mounted && q != _networkQuality) {
          setState(() => _networkQuality = q);
        }
      } catch (_) {}
    });
  }

  void _setupPeerConnection() {
    _pc!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null) {
        return;
      }
      _ws!.sendCallSignal(widget.peer.id, 'ice', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }, widget.isVideoCall);
    };
    _pc!.onTrack = (event) {
      debugPrint(
        'onTrack event: ${event.track.kind}, streams: ${event.streams.length}',
      );
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        _remoteStream = stream;
        debugPrint(
          'Remote stream received: ${stream.id}, tracks: ${stream.getTracks().length}',
        );

        // Для голосовых звонков убеждаемся, что аудио треки включены
        if (!widget.isVideoCall) {
          for (var track in stream.getAudioTracks()) {
            debugPrint(
              'Remote audio track: enabled=${track.enabled}, kind=${track.kind}',
            );
            if (!track.enabled) {
              track.enabled = true;
              debugPrint('Enabled remote audio track');
            }
          }
        }

        if (_renderersInitialized) {
          _remoteRenderer.srcObject = stream;
        }
        if (mounted) {
          setState(() {});
        }
      } else {
        // Если потоков нет, но есть трек - создаем новый поток для него
        debugPrint(
          'Track without stream: ${event.track.kind}, enabled: ${event.track.enabled}',
        );
        // Для голосовых звонков убеждаемся, что аудио трек включен
        if (!widget.isVideoCall &&
            event.track.kind == 'audio' &&
            !event.track.enabled) {
          event.track.enabled = true;
          debugPrint('Enabled remote audio track (no stream)');
        }
        // Обновляем состояние, возможно поток появится позже
        if (mounted) {
          setState(() {});
        }
      }
    };
    _pc!.onConnectionState = (state) {
      debugPrint('PeerConnection connectionState: $state');
      if (mounted) {
        setState(() {});
      }
    };
    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // При временном разрыве соединения не завершаем звонок сразу
        // Даем время на восстановление (ICE может восстановить соединение)
        if (mounted) {
          setState(() {
            // Обновляем состояние, но не завершаем звонок
          });
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        // Только при полном провале или закрытии завершаем звонок
        if (mounted) {
          _endCall();
        }
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // Восстановление соединения
        if (mounted) {
          setState(() {
            // Обновляем состояние при восстановлении
          });
        }
      }
    };
  }

  void _handleSignal(CallSignal s) async {
    if (s.signal == 'hangup') {
      // При получении hangup останавливаем все треки локального потока
      if (mounted) {
        // Останавливаем все треки локального потока
        _localStream?.getTracks().forEach((track) {
          track.stop();
        });

        // Для голосовых звонков сразу завершаем звонок (как телефонный звонок)
        // Для видеозвонков переводим в состояние ожидания переподключения
        if (!widget.isVideoCall) {
          // Голосовой звонок - завершаем сразу
          _endCall();
        } else {
          // Видеозвонок - переводим в состояние ожидания переподключения
          setState(() {
            _state = 'peer_disconnected';
            _remoteStream = null;
            _remoteRenderer.srcObject = null;
          });
          // Закрываем PeerConnection, но не завершаем звонок полностью
          await _pc?.close();
          _pc = null;
          _offerReceived = false;
          _isConnecting = false;

          // Проверяем обновления когда собеседник вышел из звонка
          if (mounted) {
            try {
              context.read<AppUpdateService>().checkForUpdates();
            } catch (_) {
              // Игнорируем ошибки проверки обновлений
            }
          }
        }
      }
      return;
    }
    if (s.signal == 'reject') {
      // При reject завершаем звонок полностью (собеседник отклонил)
      if (mounted) {
        _endCall();
      }
      return;
    }
    if (s.signal == 'offer' && s.payload != null) {
      if (_state == 'init') {
        setState(() => _state = 'ringing');
        return;
      }
      if (_state == 'ringing') {
        return;
      }

      // Определяем тип звонка из сигнала
      final incomingIsVideoCall = s.isVideoCall ?? true;

      // Если пришел offer в состоянии peer_disconnected, это переподключение - обрабатываем
      if (_state == 'peer_disconnected') {
        // Сбрасываем флаг для обработки нового offer
        _offerReceived = false;
        // Очищаем старые потоки и PeerConnection перед созданием нового
        await _cleanupForReconnect();
      }

      // Защита от дублирующих offer
      if (_offerReceived && _pc != null) {
        debugPrint('Duplicate offer received, ignoring');
        return;
      }
      _offerReceived = true;

      try {
        setState(() => _isConnecting = true);
        await _renderersFuture;

        // Если тип звонка изменился или поток не существует, получаем новый медиа поток
        final needsNewMedia =
            _localStream == null || (incomingIsVideoCall != widget.isVideoCall);

        if (needsNewMedia) {
          // Останавливаем старые треки перед получением новых
          _localStream?.getTracks().forEach((track) {
            track.stop();
          });
          await _localStream?.dispose();
          _localStream = null;

          // Обновляем тип звонка
          if (incomingIsVideoCall != widget.isVideoCall) {
            // Обновляем состояние виджета через setState
            // Но так как widget.isVideoCall - это final, нужно пересоздать экран
            // Пока просто используем тип из сигнала для обработки
          }

          await _getUserMedia(
            videoDeviceId: null,
            audioDeviceId: null,
            isVideoCall: incomingIsVideoCall,
          );
        }

        // Закрываем старый PeerConnection если он существует
        await _pc?.close();
        _pc = null;

        _pc = await createPeerConnection(WebRTCConstants.iceServers, {});
        _setupPeerConnection();
        debugPrint(
          'Adding local tracks (handle offer): ${_localStream!.getTracks().length}, isVideoCall: $incomingIsVideoCall',
        );
        // Добавляем треки в PeerConnection перед применением mute
        for (var track in _localStream!.getTracks()) {
          debugPrint('Adding track: ${track.kind}, enabled: ${track.enabled}');
          await _pc!.addTrack(track, _localStream!);
        }
        // Применяем mute после добавления треков (используем тип из сигнала)
        _applyInitialMuteForCallType(incomingIsVideoCall);
        // Для голосовых звонков убеждаемся, что аудио треки включены
        if (!incomingIsVideoCall) {
          for (var track in _localStream!.getAudioTracks()) {
            if (!track.enabled) {
              track.enabled = true;
              debugPrint(
                'Enabled local audio track for voice call (handle offer)',
              );
            }
          }
        }
        var desc = RTCSessionDescription(
          s.payload!['sdp'] as String,
          s.payload!['type'] as String,
        );
        await _pc!.setRemoteDescription(desc);
        // Обрабатываем отложенные ICE кандидаты перед созданием answer
        for (var c in _pendingCandidates) {
          try {
            await _pc!.addCandidate(
              RTCIceCandidate(
                c['candidate'] as String,
                c['sdpMid'] as String?,
                c['sdpMLineIndex'] as int?,
              ),
            );
          } catch (e) {
            debugPrint('Error adding pending candidate: $e');
          }
        }
        _pendingCandidates.clear();
        var answer = await _pc!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': incomingIsVideoCall,
        });
        await _pc!.setLocalDescription(answer);
        _ws!.sendCallSignal(widget.peer.id, 'answer', {
          'sdp': answer.sdp,
          'type': answer.type,
        }, incomingIsVideoCall);
        if (mounted) {
          AppSoundService.instance.stopRingtone();
          setState(() {
            _state = 'connected';
            _isConnecting = false;
          });
          _startStatsPolling();
        }
      } catch (e) {
        if (mounted) {
          AppSoundService.instance.stopRingtone();
          setState(() {
            _state = 'ended';
            _error = MediaUtils.getMediaErrorMessage(e);
            _isConnecting = false;
          });
        }
      }
      return;
    }
    if (s.signal == 'answer' && s.payload != null) {
      if (_pc == null) {
        return;
      }
      try {
        var desc = RTCSessionDescription(
          s.payload!['sdp'] as String,
          s.payload!['type'] as String,
        );
        await _pc!.setRemoteDescription(desc);
        // Обрабатываем отложенные ICE кандидаты
        for (var c in _pendingCandidates) {
          try {
            await _pc!.addCandidate(
              RTCIceCandidate(
                c['candidate'] as String,
                c['sdpMid'] as String?,
                c['sdpMLineIndex'] as int?,
              ),
            );
          } catch (e) {
            debugPrint('Error adding pending candidate: $e');
          }
        }
        _pendingCandidates.clear();
        if (mounted) {
          AppSoundService.instance.stopRingtone();
          setState(() {
            _state = 'connected';
            _isConnecting =
                false; // Соединение установлено после получения answer
          });
          _startStatsPolling();
        }
      } catch (e) {
        debugPrint('Error handling answer signal: $e');
        if (mounted) {
          setState(() {
            _state = 'ended';
            _error = 'Ошибка при установке соединения';
            _isConnecting = false;
          });
        }
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
    logUserAction('call_accept', {
      'peerId': widget.peer.id,
      'isVideo': widget.isVideoCall,
    });
    final offerPayload = widget.initialSignal?.payload;
    if (offerPayload == null) {
      return;
    }
    setState(() {
      _state = 'init';
      _isConnecting = true;
    });
    try {
      await _renderersFuture;

      // Получаем медиа только если еще не получили
      if (_localStream == null) {
        await _getUserMedia(videoDeviceId: null, audioDeviceId: null);
      }

      _pc = await createPeerConnection(WebRTCConstants.iceServers, {});
      _setupPeerConnection();
      // Добавляем треки в PeerConnection перед применением mute
      for (var track in _localStream!.getTracks()) {
        debugPrint(
          'Adding track to PeerConnection (accept): ${track.kind}, enabled: ${track.enabled}',
        );
        await _pc!.addTrack(track, _localStream!);
      }
      // Применяем mute после добавления треков
      _applyInitialMute();
      // Для голосовых звонков убеждаемся, что аудио треки включены
      if (!widget.isVideoCall) {
        for (var track in _localStream!.getAudioTracks()) {
          if (!track.enabled) {
            track.enabled = true;
            debugPrint('Enabled local audio track for voice call (accept)');
          }
        }
      }
      var desc = RTCSessionDescription(
        offerPayload['sdp'] as String,
        offerPayload['type'] as String,
      );
      await _pc!.setRemoteDescription(desc);
      // Обрабатываем отложенные ICE кандидаты перед созданием answer
      for (var c in _pendingCandidates) {
        try {
          await _pc!.addCandidate(
            RTCIceCandidate(
              c['candidate'] as String,
              c['sdpMid'] as String?,
              c['sdpMLineIndex'] as int?,
            ),
          );
        } catch (e) {
          debugPrint('Error adding pending candidate: $e');
        }
      }
      _pendingCandidates.clear();
      var answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideoCall,
      });
      await _pc!.setLocalDescription(answer);
      _ws!.sendCallSignal(widget.peer.id, 'answer', {
        'sdp': answer.sdp,
        'type': answer.type,
      }, widget.isVideoCall);
      if (mounted) {
        AppSoundService.instance.stopRingtone();
        setState(() {
          _state = 'connected';
          _isConnecting =
              false; // Соединение установлено после получения answer
        });
        _startStatsPolling();
      }
    } catch (e) {
      if (mounted) {
        AppSoundService.instance.stopRingtone();
        setState(() {
          _state = 'ended';
          _error = MediaUtils.getMediaErrorMessage(e);
          _isConnecting = false;
        });
      }
    }
  }

  void _rejectCall() {
    logUserAction('call_reject', {'peerId': widget.peer.id});
    // Сообщение о пропущенном звонке создается автоматически на сервере при отправке сигнала reject
    _ws!.sendCallSignal(widget.peer.id, 'reject', null, widget.isVideoCall);
    _endCall();
  }

  void _hangUp() {
    logUserAction('call_hangup', {'peerId': widget.peer.id});
    _ws!.sendCallSignal(widget.peer.id, 'hangup', null, widget.isVideoCall);
    _endCall();
  }

  Future<void> _endCall() async {
    AppSoundService.instance.stopRingtone();
    _signalSub?.cancel();
    if (_screenShareEnabled) {
      await _stopScreenShare();
    }
    _localRenderer.srcObject = null;
    // Очищаем состояние минимизации
    if (mounted) {
      context.read<CallMinimizedService>().endCall();
    }
    _remoteRenderer.srcObject = null;
    _screenRenderer.srcObject = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    _offerReceived = false;
    _isConnecting = false;
    // Сообщение о пропущенном звонке создается автоматически на сервере при отправке сигнала reject
    if (mounted) {
      setState(() => _state = 'ended');
      Navigator.of(context).pop();
    }

    // Проверяем обновления при выходе из звонка
    if (mounted) {
      try {
        context.read<AppUpdateService>().checkForUpdates();
      } catch (_) {
        // Игнорируем ошибки проверки обновлений
      }
    }
  }

  Future<void> _loadMediaDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (mounted) {
        setState(() => _mediaDevices = devices);
      }
    } catch (_) {}
  }

  List<MediaDeviceInfo> get _videoInputs =>
      _mediaDevices.where((d) => d.kind == 'videoinput').toList();
  List<MediaDeviceInfo> get _audioInputs =>
      _mediaDevices.where((d) => d.kind == 'audioinput').toList();

  @override
  void dispose() {
    resetTabTitle();
    AppSoundService.instance.setInCall(false);
    AppSoundService.instance.stopRingtone();
    _signalSub?.cancel();
    _statsTimer?.cancel();
    try {
      context.read<CallMinimizedService>().clearActiveCall();
    } catch (_) {}
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
    final canPopNormally = _state == 'ended';
    return PopScope(
      canPop: canPopNormally,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !canPopNormally) {
          _minimizeCall();
        }
      },
      child: _buildCallContent(context),
    );
  }

  Widget _buildCallContent(BuildContext context) {
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
    final isControlsVisible =
        _state == 'calling' ||
        _state == 'connected' ||
        _state == 'peer_disconnected';

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoLayout(),
            if (widget.isVideoCall) _buildOverlayTitle(),
            if (_state == 'connected') _buildNetworkQualityIndicator(),
            // Показываем превью локального видео только для видеозвонков в режиме докладчика или обычном режиме когда есть удаленное видео
            // НЕ показываем в режиме "рядом" (там локальное видео уже в основном layout)
            if (widget.isVideoCall &&
                _state == 'connected' &&
                _renderersInitialized &&
                _remoteStream != null &&
                _layout != CallLayout.sideBySide &&
                _localStream != null)
              _buildLocalPreview(isControlsVisible),
            if (_state == 'ringing') _buildIncomingControls(),
            if (isControlsVisible) ...[
              if (widget.isVideoCall) _buildLayoutSwitcher(),
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    // Для голосовых звонков показываем аватар вместо видео
    if (!widget.isVideoCall) {
      return _buildVoiceCallLayout();
    }
    switch (_layout) {
      case CallLayout.sideBySide:
        return _buildSideBySideLayout();
      case CallLayout.speaker:
      case CallLayout.normal:
        return _buildSpeakerLayout();
    }
  }

  Widget _buildVoiceCallLayout() {
    final showRemote = _state == 'connected' && _remoteStream != null;
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 80,
              backgroundColor: Colors.blue.shade700,
              backgroundImage:
                  widget.peer.avatarUrl != null &&
                      widget.peer.avatarUrl!.isNotEmpty
                  ? NetworkImage(widget.peer.avatarUrl!)
                  : null,
              child:
                  widget.peer.avatarUrl == null ||
                      widget.peer.avatarUrl!.isEmpty
                  ? Text(
                      widget.peer.displayName.isNotEmpty
                          ? widget.peer.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 48),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.peer.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (showRemote)
              const Text(
                'Разговор',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              )
            else if (_state == 'calling')
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Вызов...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              )
            else if (_state == 'ringing')
              const Text(
                'Входящий звонок',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              )
            else if (_state == 'connected' && !showRemote)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Подключение...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerLayout() {
    final showRemote = _state == 'connected' && _remoteStream != null;
    // Показываем локальное видео когда:
    // 1. Есть локальный поток и (звонок calling/connected/peer_disconnected) И нет удаленного потока ИЛИ
    // 2. Есть локальный поток и есть удаленный поток (для режима докладчика локальное показывается отдельно)
    final showLocal =
        _localStream != null &&
        ((_state == 'calling' ||
                    _state == 'connected' ||
                    _state == 'peer_disconnected') &&
                !showRemote ||
            (_state == 'connected' &&
                showRemote &&
                _layout == CallLayout.speaker));
    final isConnecting = _state == 'connected' && _isConnecting && !showRemote;
    final isWaiting =
        _state == 'calling' ||
        (_state == 'connected' && !showRemote && !isConnecting) ||
        _state == 'peer_disconnected';

    return Stack(
      fit: StackFit.expand,
      children: [
        // Удаленное видео (приоритет 1)
        if (showRemote)
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        // Локальное видео (приоритет 2) - показываем когда calling или connected без remote
        else if (showLocal && !_screenShareEnabled)
          Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                _localRenderer,
                mirror: _isFrontCamera, // Зеркалим только переднюю камеру
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              // Показываем оверлей с информацией о втором участнике когда ожидаем подключения
              if (isWaiting)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue.shade700,
                          backgroundImage:
                              widget.peer.avatarUrl != null &&
                                  widget.peer.avatarUrl!.isNotEmpty
                              ? NetworkImage(widget.peer.avatarUrl!)
                              : null,
                          child:
                              widget.peer.avatarUrl == null ||
                                  widget.peer.avatarUrl!.isEmpty
                              ? Text(
                                  widget.peer.displayName.isNotEmpty
                                      ? widget.peer.displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.peer.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_state == 'calling')
                          const Text(
                            'Ожидание подключения...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          )
                        else if (_state == 'peer_disconnected')
                          const Text(
                            'Собеседник отключился. Ожидание переподключения...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          )
                        else
                          const Text(
                            'Подключение...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          )
        // Демонстрация экрана
        else if (_state == 'connected' && _screenShareEnabled)
          RTCVideoView(
            _screenRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          )
        // Индикатор подключения
        else if (isConnecting)
          Container(
            color: const Color(0xFF1A1A1A),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'Подключение...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        // Пустой экран
        else
          Container(color: const Color(0xFF1A1A1A)),
      ],
    );
  }

  Widget _buildSideBySideLayout() {
    final showRemote = _state == 'connected' && _remoteStream != null;
    final showLocal = _localStream != null || _screenShareEnabled;
    final isConnecting = _state == 'connected' && _isConnecting && !showRemote;
    final isWaiting =
        _state == 'calling' ||
        (_state == 'connected' && !showRemote && !isConnecting) ||
        _state == 'peer_disconnected';

    return Row(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: showLocal
                ? (_screenShareEnabled
                      ? RTCVideoView(
                          _screenRenderer,
                          objectFit: RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitContain,
                        )
                      : RTCVideoView(
                          _localRenderer,
                          mirror:
                              _isFrontCamera, // Зеркалим только переднюю камеру
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ))
                : const Center(
                    child: Text('Вы', style: TextStyle(color: Colors.white70)),
                  ),
          ),
        ),
        Container(width: 2, color: Colors.grey.shade800),
        Expanded(
          child: Container(
            color: Colors.black,
            child: showRemote
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : isConnecting
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.orange),
                        const SizedBox(height: 8),
                        Text(
                          'Подключение...',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.blue.shade700,
                          backgroundImage:
                              widget.peer.avatarUrl != null &&
                                  widget.peer.avatarUrl!.isNotEmpty
                              ? NetworkImage(widget.peer.avatarUrl!)
                              : null,
                          child:
                              widget.peer.avatarUrl == null ||
                                  widget.peer.avatarUrl!.isEmpty
                              ? Text(
                                  widget.peer.displayName.isNotEmpty
                                      ? widget.peer.displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.peer.displayName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (isWaiting)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _state == 'calling'
                                  ? 'Ожидание...'
                                  : _state == 'peer_disconnected'
                                  ? 'Отключен'
                                  : 'Подключение...',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkQualityIndicator() {
    return Positioned(
      top: widget.isVideoCall ? 52 : 8,
      right: 16,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_networkQualityIcon, color: _networkQualityColor, size: 18),
              const SizedBox(width: 4),
              Text(
                _networkQualityLabel,
                style: TextStyle(color: _networkQualityColor, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _networkQualityIcon {
    switch (_networkQuality) {
      case NetworkQuality.excellent:
        return Icons.signal_cellular_4_bar;
      case NetworkQuality.good:
        return Icons.signal_cellular_alt;
      case NetworkQuality.fair:
        return Icons.signal_cellular_alt_2_bar;
      case NetworkQuality.poor:
        return Icons.signal_cellular_alt_1_bar;
      case NetworkQuality.unknown:
        return Icons.signal_cellular_alt;
    }
  }

  Color get _networkQualityColor {
    switch (_networkQuality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return Colors.greenAccent;
      case NetworkQuality.fair:
        return Colors.orange;
      case NetworkQuality.poor:
        return Colors.redAccent;
      case NetworkQuality.unknown:
        return Colors.white54;
    }
  }

  String get _networkQualityLabel {
    switch (_networkQuality) {
      case NetworkQuality.excellent:
        return 'Отлично';
      case NetworkQuality.good:
        return 'Хорошо';
      case NetworkQuality.fair:
        return 'Средне';
      case NetworkQuality.poor:
        return 'Плохо';
      case NetworkQuality.unknown:
        return '...';
    }
  }

  Widget _buildOverlayTitle() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peer.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
                Text(
                  _state == 'calling'
                      ? 'Вызов...'
                      : _state == 'ringing'
                      ? widget.isVideoCall
                            ? 'Входящий видеозвонок'
                            : 'Входящий звонок'
                      : _state == 'connected'
                      ? widget.isVideoCall
                            ? 'Видеозвонок'
                            : 'Голосовой звонок'
                      : _state == 'peer_disconnected'
                      ? 'Ожидание переподключения...'
                      : '...',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          if (_state == 'connected')
            IconButton(
              icon: const Icon(Icons.minimize, color: Colors.white),
              onPressed: _minimizeCall,
              tooltip: 'Свернуть',
            ),
        ],
      ),
    );
  }

  void _minimizeCall() {
    final minimizedService = context.read<CallMinimizedService>();
    minimizedService.minimizeCall(widget.peer, widget.isVideoCall);
    // Не закрываем экран полностью, а просто скрываем его
    // Это позволит восстановить состояние при разворачивании
    Navigator.of(context).pop();
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
              ? RTCVideoView(
                  _screenRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                )
              : RTCVideoView(
                  _localRenderer,
                  mirror: _isFrontCamera, // Зеркалим только переднюю камеру
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CallActionButton.reject(onPressed: _rejectCall),
          const SizedBox(width: 32),
          CallActionButton.accept(
            onPressed: _acceptCall,
            icon: widget.isVideoCall ? Icons.videocam : Icons.phone,
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutSwitcher() {
    if (_state != 'connected') {
      return const SizedBox.shrink();
    }
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
    return CallLayoutButton(
      onPressed: () => setState(() => _layout = layout),
      icon: icon,
      tooltip: tooltip,
      isSelected: selected,
    );
  }

  Widget _buildBottomControls(String myName) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            CallControlButton.participants(
              onPressed: () {
                logUserAction('call_toggle_panel', {'show': !_showPanel});
                setState(() => _showPanel = !_showPanel);
              },
              isExpanded: _showPanel,
              size: 48,
            ),
            CallControlButton.microphone(
              onPressed: _toggleMic,
              isEnabled: _micEnabled,
              size: 48,
            ),
            if (widget.isVideoCall)
              CallControlButton.camera(
                onPressed: _toggleCamera,
                isEnabled: _cameraEnabled,
                size: 48,
              ),
            if (widget.isVideoCall) ...[
              CallControlButton.screenShare(
                onPressed: _toggleScreenShare,
                isEnabled: _screenShareEnabled,
                size: 48,
              ),
              CallControlButton.switchCamera(
                onPressed: _screenShareEnabled ? null : _switchCamera,
                size: 48,
              ),
            ],
            CallActionButton.reject(
              onPressed: _hangUp,
              size: 48,
              padding: const EdgeInsets.all(12),
            ),
          ],
        ),
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
                  logUserAction('call_panel_tab', {
                    'index': i,
                    'tab': i == 0 ? 'participants' : 'settings',
                  });
                  setState(() => _panelTabIndex = i);
                  if (i == 1) {
                    _loadMediaDevices();
                  }
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
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white),
        ),
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
                Icon(
                  micOn == true ? Icons.mic : Icons.mic_off,
                  color: micOn == true ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Icon(
                  videoOn == true ? Icons.videocam : Icons.videocam_off,
                  color: videoOn == true ? Colors.green : Colors.red,
                  size: 20,
                ),
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
          const Text(
            'Камера',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _selectedVideoDeviceId ?? videoInputs.first.deviceId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: const Color(0xFF333333),
            style: const TextStyle(color: Colors.white),
            items: videoInputs
                .map(
                  (d) => DropdownMenuItem(
                    value: d.deviceId,
                    child: Text(
                      d.label.isNotEmpty
                          ? d.label
                          : 'Камера ${d.deviceId.substring(0, 8)}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null) {
                return;
              }
              setState(() => _selectedVideoDeviceId = id);
              _getUserMedia(
                videoDeviceId: id,
                audioDeviceId: _selectedAudioDeviceId,
              ).then((_) {
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
          const Text(
            'Микрофон',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _selectedAudioDeviceId ?? audioInputs.first.deviceId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: const Color(0xFF333333),
            style: const TextStyle(color: Colors.white),
            items: audioInputs
                .map(
                  (d) => DropdownMenuItem(
                    value: d.deviceId,
                    child: Text(
                      d.label.isNotEmpty
                          ? d.label
                          : 'Микрофон ${d.deviceId.substring(0, 8)}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null) {
                return;
              }
              setState(() => _selectedAudioDeviceId = id);
              _getUserMedia(
                videoDeviceId: _selectedVideoDeviceId,
                audioDeviceId: id,
              ).then((_) {
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
            child: Text(
              'Нет доступных устройств',
              style: TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }
}
