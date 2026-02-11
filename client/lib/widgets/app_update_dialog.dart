import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_update_service.dart';

/// Виджет для автоматического показа диалога об обновлении
class AppUpdateDialogListener extends StatefulWidget {
  final Widget child;

  const AppUpdateDialogListener({super.key, required this.child});

  @override
  State<AppUpdateDialogListener> createState() =>
      _AppUpdateDialogListenerState();
}

class _AppUpdateDialogListenerState extends State<AppUpdateDialogListener> {
  bool _hasShownDialog = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppUpdateService>(
      builder: (context, updateService, _) {
        // Показываем диалог при первом обнаружении обновления
        if (updateService.hasUpdate && !_hasShownDialog && mounted) {
          _hasShownDialog = true;
          // Используем Future.microtask чтобы не блокировать build
          Future.microtask(() {
            if (!mounted) {
              return;
            }
            _showUpdateDialog(context, updateService);
          });
        }

        // Сбрасываем флаг если обновление было закрыто
        if (!updateService.hasUpdate && _hasShownDialog) {
          _hasShownDialog = false;
        }

        return widget.child;
      },
    );
  }

  void _showUpdateDialog(BuildContext context, AppUpdateService updateService) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.system_update,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Приложение обновилось',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Доступна новая версия приложения.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (updateService.latestVersion != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Версия: ${updateService.latestVersion}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Рекомендуется обновить приложение для получения последних улучшений и исправлений.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                updateService.dismissUpdate();
                Navigator.of(context).pop();
              },
              child: Text(
                'Позже',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                updateService.updateApp();
              },
              child: const Text('Обновить'),
            ),
          ],
        );
      },
    );
  }
}
