import 'dart:io';
import 'package:video_player/video_player.dart';
import 'temp_file_io.dart';

Future<VideoPlayerController?> createVideoControllerFromBytes(
  List<int> bytes,
) async {
  final path = await writeTempBytes(bytes, 'video_note.mp4');
  final controller = VideoPlayerController.file(File(path));
  await controller.initialize();
  controller.setLooping(false);
  return controller;
}
