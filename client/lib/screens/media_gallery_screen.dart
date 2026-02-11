import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../widgets/app_back_button.dart';
import 'image_preview_screen.dart';

class MediaGalleryScreen extends StatefulWidget {
  final User? peer;
  final Group? group;

  const MediaGalleryScreen({super.key, this.peer, this.group})
    : assert(
        peer != null || group != null,
        'Either peer or group must be provided',
      );

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen>
    with SingleTickerProviderStateMixin {
  List<MediaItem> _media = [];
  bool _loading = true;
  String? _error;
  String _selectedType = 'all'; // 'all', 'photo', 'video'
  late TabController _tabController;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedType = ['all', 'photo', 'video'][_tabController.index];
          _media = [];
          _hasMore = true;
        });
        _loadMedia();
      }
    });
    _loadMedia();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMedia({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn) return;

      final api = Api(auth.token);
      final offset = loadMore ? _media.length : 0;

      final response = widget.peer != null
          ? await api.getMedia(
              widget.peer!.id,
              type: _selectedType,
              limit: 50,
              offset: offset,
            )
          : await api.getGroupMedia(
              widget.group!.id,
              type: _selectedType,
              limit: 50,
              offset: offset,
            );

      final data = response['data'] as List<dynamic>;
      final pagination = response['pagination'] as Map<String, dynamic>;

      final newMedia = data
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      setState(() {
        if (loadMore) {
          _media.addAll(newMedia);
        } else {
          _media = newMedia;
        }
        _hasMore = pagination['hasMore'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openMedia(MediaItem item, int index) {
    if (item.type == 'photo') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            imageUrl: item.url,
            filename: item.filename ?? 'image.jpg',
          ),
        ),
      );
    } else if (item.type == 'video') {
      // Открываем видео в браузере или используем video_player если установлен
      // Navigator.push(
      //   context,
      //   MaterialPageRoute(
      //     builder: (_) => _VideoViewerScreen(videoUrl: item.url),
      //   ),
      // );
      // Пока просто показываем snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Просмотр видео будет доступен после установки video_player',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          widget.peer != null
              ? 'Медиа ${widget.peer!.displayName}'
              : 'Медиа ${widget.group!.name}',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Все'),
            Tab(text: 'Фото'),
            Tab(text: 'Видео'),
          ],
        ),
      ),
      body: _loading && _media.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _media.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _loadMedia(),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            )
          : _media.isEmpty
          ? Center(
              child: Text(
                _selectedType == 'all'
                    ? 'Нет медиа файлов'
                    : _selectedType == 'photo'
                    ? 'Нет фотографий'
                    : 'Нет видео',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadMedia(),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _media.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _media.length) {
                    // Загружаем больше при прокрутке
                    _loadMedia(loadMore: true);
                    return const Center(child: CircularProgressIndicator());
                  }

                  final item = _media[index];
                  return _MediaThumbnail(
                    item: item,
                    onTap: () => _openMedia(item, index),
                  );
                },
              ),
            ),
    );
  }
}

class MediaItem {
  final int id;
  final int messageId;
  final int? groupId;
  final int senderId;
  final String senderDisplayName;
  final String url;
  final String? thumbnailUrl;
  final String? filename;
  final String type; // 'photo', 'video', 'file'
  final int? durationSec;
  final String createdAt;
  final bool encrypted;

  MediaItem({
    required this.id,
    required this.messageId,
    this.groupId,
    required this.senderId,
    required this.senderDisplayName,
    required this.url,
    this.thumbnailUrl,
    this.filename,
    required this.type,
    this.durationSec,
    required this.createdAt,
    required this.encrypted,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as int,
      messageId: json['messageId'] as int,
      groupId: json['groupId'] as int?,
      senderId: json['senderId'] as int,
      senderDisplayName: json['senderDisplayName'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      filename: json['filename'] as String?,
      type: json['type'] as String,
      durationSec: json['durationSec'] as int?,
      createdAt: json['createdAt'] as String,
      encrypted: json['encrypted'] as bool? ?? false,
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _MediaThumbnail({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.type == 'photo')
            Image.network(
              item.thumbnailUrl ?? item.url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image),
                );
              },
            )
          else if (item.type == 'video')
            Stack(
              fit: StackFit.expand,
              children: [
                // Показываем placeholder для видео (можно использовать thumbnail если есть)
                Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.videocam, size: 40),
                ),
                Container(
                  color: Colors.black.withValues(alpha:0.3),
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_filled,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                if (item.durationSec != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha:0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(item.durationSec!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else
            Container(
              color: Colors.grey[300],
              child: const Icon(Icons.insert_drive_file, size: 40),
            ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

// Video viewer будет добавлен после установки video_player и chewie
// class _VideoViewerScreen extends StatefulWidget {
//   final String videoUrl;
//   const _VideoViewerScreen({required this.videoUrl});
//   @override
//   State<_VideoViewerScreen> createState() => _VideoViewerScreenState();
// }
// ...
