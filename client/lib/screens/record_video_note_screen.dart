import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';

class RecordVideoNoteScreen extends StatefulWidget {
  final int peerId;
  final String? peerPublicKey;

  const RecordVideoNoteScreen({super.key, required this.peerId, this.peerPublicKey});

  @override
  State<RecordVideoNoteScreen> createState() => _RecordVideoNoteScreenState();
}

class _RecordVideoNoteScreenState extends State<RecordVideoNoteScreen> {
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  bool _recording = false;
  bool _loading = true;
  String? _error;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  String _cameraErrorMessage(Object e) {
    if (kIsWeb) {
      // В браузере камера работает только по HTTPS; по HTTP браузер блокирует доступ
      return 'Видеокружок в браузере доступен только по HTTPS. Откройте сайт по https:// или используйте приложение на телефоне.';
    }
    if (e.toString().toLowerCase().contains('permission')) return 'Нет доступа к камере. Разрешите доступ в настройках.';
    return 'Ошибка камеры. Проверьте, что приложению разрешён доступ к камере.';
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _loading = false;
          _error = kIsWeb
              ? 'Видеокружок в браузере доступен только по HTTPS. Откройте сайт по https:// или используйте приложение на телефоне.'
              : 'Камера недоступна';
        });
        return;
      }
      final camera = _cameras!.length > 1 ? _cameras![1] : _cameras!.first;
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.jpeg,
        enableAudio: true,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _cameraErrorMessage(e);
      });
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _recording) return;
    try {
      await _controller!.startVideoRecording();
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _recording) setState(() => _recordSeconds++);
      });
    } catch (e) {
      setState(() => _error = 'Ошибка записи');
    }
  }

  Future<void> _stopAndSend() async {
    if (_controller == null || !_recording) return;
    _recordTimer?.cancel();
    setState(() => _recording = false);
    try {
      final xFile = await _controller!.stopVideoRecording();
      var bytes = await xFile.readAsBytes();
      var encrypted = false;
      if (widget.peerPublicKey != null) {
        final e2ee = E2EEService();
        final enc = await e2ee.encryptBytes(Uint8List.fromList(bytes), widget.peerPublicKey);
        if (enc != null) {
          bytes = enc;
          encrypted = true;
        }
      }
      final name = xFile.name;
      final filename = name.isNotEmpty ? name : 'video_note_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final durationSec = _recordSeconds > 0 ? _recordSeconds : 1;
      final auth = context.read<AuthService>();
      final api = Api(auth.token);
      final msg = await api.sendVideoNoteMessage(widget.peerId, bytes, filename, durationSec, attachmentEncrypted: encrypted);
      if (!mounted) return;
      Navigator.of(context).pop({'message': msg});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Ошибка отправки');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Видеокружок')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                AppBar(
                  title: const Text('Видеокружок'),
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                ),
                const Spacer(),
                if (_recording)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '$_recordSeconds сек',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_recording)
                        GestureDetector(
                          onTap: _startRecording,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 48),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _stopAndSend,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: const Icon(Icons.stop, color: Colors.white, size: 48),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
