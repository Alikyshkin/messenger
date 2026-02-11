import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/video_controller.dart';

class VideoNoteBubble extends StatefulWidget {
  final String? videoUrl;
  final Future<List<int>>? videoBytesFuture;
  final int? durationSec;
  final bool isMine;

  const VideoNoteBubble({
    super.key,
    this.videoUrl,
    this.videoBytesFuture,
    this.durationSec,
    required this.isMine,
  });

  @override
  State<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends State<VideoNoteBubble> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.videoBytesFuture != null) {
      widget.videoBytesFuture!.then((bytes) async {
        if (!mounted) return;
        try {
          final controller = await createVideoControllerFromBytes(bytes);
          if (!mounted) return;
          if (controller != null) {
            setState(() {
              _controller = controller;
              _initialized = true;
            });
          } else {
            setState(
              () => _error = 'Веб: зашифрованное видео не воспроизводится',
            );
          }
        } catch (e) {
          if (mounted) setState(() => _error = 'Ошибка загрузки');
        }
      });
    } else if (widget.videoUrl != null) {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!))
            ..initialize().then((_) {
              if (mounted) {
                setState(() => _initialized = true);
                _controller!.setLooping(false);
              }
            });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 200.0;
    if (_error != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black87,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        if (!_initialized) return;
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
        setState(() {});
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (_initialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              if (_initialized && !_controller!.value.isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
