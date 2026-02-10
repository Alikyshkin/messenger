import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/download_file.dart';
import '../widgets/app_back_button.dart';

/// Полноэкранный просмотр изображения. По тапу — превью, в меню (⋮) — «Скачать».
class ImagePreviewScreen extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String filename;
  final Future<Uint8List>? bytesFuture;

  const ImagePreviewScreen({
    super.key,
    this.imageBytes,
    this.imageUrl,
    required this.filename,
    this.bytesFuture,
  });

  Future<void> _download(BuildContext context) async {
    Uint8List? bytes = imageBytes;
    if (bytes == null && bytesFuture != null) {
      bytes = await bytesFuture;
    }
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось загрузить файл')));
      return;
    }
    try {
      await saveOrDownloadFile(bytes, filename);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось сохранить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Text(
          filename,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'download') _download(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 12),
                    Text('Скачать'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: imageBytes != null
              ? Image.memory(
                  imageBytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                )
              : imageUrl != null
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      },
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                    )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
