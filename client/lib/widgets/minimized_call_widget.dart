import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/call_minimized_service.dart';
import '../widgets/user_avatar.dart';
import '../utils/app_page_route.dart';
import '../screens/call_screen.dart';
import '../screens/group_call_screen.dart';
import '../utils/user_action_logger.dart';

/// Компактный вид свернутого звонка (мини-окно)
class MinimizedCallWidget extends StatelessWidget {
  const MinimizedCallWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Используем Provider.of с безопасной проверкой
    CallMinimizedService? service;
    try {
      service = Provider.of<CallMinimizedService>(context, listen: true);
    } catch (e) {
      // Provider недоступен - возможно виджет используется вне дерева Provider
      // Это нормально, если виджет еще не добавлен в дерево или Provider не инициализирован
      return const SizedBox.shrink();
    }

    if (!service.isMinimized) {
      return const SizedBox.shrink();
    }

    final peer = service.peer;
    final group = service.group;
    final isVideoCall = service.isVideoCall;
    final isGroupCall = service.isGroupCall;

    if (peer == null && group == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      right: 8,
      left: 8,
      child: Material(
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Tooltip(
          message: 'Нажмите для возврата к звонку',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _expandCall(context, service!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Аватар
                  if (isGroupCall && group != null)
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          backgroundImage:
                              group.avatarUrl != null &&
                                  group.avatarUrl!.isNotEmpty
                              ? NetworkImage(group.avatarUrl!)
                              : null,
                          child:
                              group.avatarUrl == null ||
                                  group.avatarUrl!.isEmpty
                              ? Icon(
                                  Icons.group,
                                  size: 24,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (peer != null)
                    Stack(
                      children: [
                        UserAvatar(user: peer, radius: 24),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(width: 12),
                  // Информация о звонке
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGroupCall && group != null
                              ? group.name
                              : peer?.displayName ?? '',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isVideoCall ? Icons.videocam : Icons.phone,
                              size: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVideoCall ? 'Видеозвонок' : 'Аудиозвонок',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Кнопка завершения
                  IconButton(
                    icon: const Icon(Icons.call_end),
                    color: Colors.red,
                    iconSize: 24,
                    onPressed: () {
                      // Завершаем звонок через сервис
                      service?.endCall();
                      // Навигация обрабатывается в экранах звонков
                    },
                    tooltip: 'Завершить звонок',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _expandCall(BuildContext context, CallMinimizedService service) {
    logUserAction('call_expand_minimized', {
      'isGroup': service.isGroupCall,
      'peerId': service.peer?.id,
      'groupId': service.group?.id,
    });
    service.expandCall();

    // Навигация к экрану звонка
    // Примечание: при минимизации экран закрывается, поэтому создается новый экран
    // Это означает, что состояние звонка (PeerConnection, потоки) теряется
    // Для полного решения проблемы нужно использовать Overlay или другой механизм
    // который не закрывает экран при минимизации
    if (service.isGroupCall && service.group != null) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) =>
              GroupCallScreen(group: service.group!, isIncoming: false),
        ),
      );
    } else if (service.peer != null) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => CallScreen(
            peer: service.peer!,
            isIncoming: false,
            isVideoCall: service.isVideoCall,
          ),
        ),
      );
    }
  }
}
