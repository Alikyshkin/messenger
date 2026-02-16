import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/temp_file.dart';
import '../utils/create_blob_url.dart';
import '../utils/revoke_blob_url.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String? audioUrl;
  final Future<List<int>>? audioBytesFuture;
  final int durationSec;
  final bool isMine;

  const VoiceMessageBubble({
    super.key,
    this.audioUrl,
    this.audioBytesFuture,
    required this.durationSec,
    required this.isMine,
  }) : assert(audioUrl != null || audioBytesFuture != null);

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  String? _blobUrl; // Для очистки blob URL на веб (только на веб)

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {});
      }
    });
    _player.positionStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Очищаем blob URL на веб
    if (_blobUrl != null) {
      revokeBlobUrl(_blobUrl!);
    }
    _player.dispose();
    super.dispose();
  }


  Future<void> _togglePlay() async {
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        if (!_initialized) {
          if (widget.audioBytesFuture != null) {
            final bytes = await widget.audioBytesFuture!;
            if (kIsWeb) {
              // Используем blob URL вместо data URI для обхода CSP
              _blobUrl = await createBlobUrlFromBytes(bytes, 'audio/mp4');
              if (_blobUrl != null) {
                await _player.setUrl(_blobUrl!);
              } else {
                // Fallback на data URI если blob не работает
                await _player.setUrl(
                  'data:audio/mp4;base64,${base64Encode(bytes)}',
                );
              }
            } else {
              final path = await writeTempBytes(bytes, 'voice.m4a');
              await _player.setFilePath(path);
            }
          } else if (widget.audioUrl != null) {
            await _player.setUrl(widget.audioUrl!);
          }
          _initialized = true;
        }
        await _player.seek(Duration.zero);
        await _player.play();
      }
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final sec = d.inSeconds;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final duration = Duration(seconds: widget.durationSec);
    final position = _player.position;
    final total = _player.duration ?? duration;
    final progress = total.inMilliseconds > 0
        ? position.inMilliseconds / total.inMilliseconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _player.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            color: color,
            size: 40,
          ),
          onPressed: _togglePlay,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: color.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDuration(position)} / ${_formatDuration(duration)}',
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
