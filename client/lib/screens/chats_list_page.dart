import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../database/local_db.dart';
import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../services/chat_list_refresh_service.dart';
import '../widgets/skeleton.dart';
import '../widgets/app_update_banner.dart';
import '../widgets/user_avatar.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../styles/app_spacing.dart';
import '../utils/user_action_logger.dart';

/// Экран списка чатов для встраивания в ShellRoute (правая часть)
class ChatsListPage extends StatefulWidget {
  const ChatsListPage({super.key});

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage>
    with AutomaticKeepAliveClientMixin {
  List<ChatPreview> _chats = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _newMessageSub;

  @override
  bool get wantKeepAlive => true;

  void _onRefreshRequested() {
    if (mounted) {
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatListRefreshService>().addListener(_onRefreshRequested);
      _load();
      context.read<WsService>().connect(context.read<AuthService>().token);
      _newMessageSub = context.read<WsService>().onNewMessage.listen((_) {
        if (mounted) _load();
      });
    });
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    try {
      context.read<ChatListRefreshService>().removeListener(
        _onRefreshRequested,
      );
    } catch (_) {}
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await LocalDb.getChats();
    if (cached.isNotEmpty && mounted) {
      setState(() => _chats = cached);
    }
    try {
      final api = Api(auth.token);
      final list = await api.getChats();
      if (!mounted) return;

      final filteredList = <ChatPreview>[];
      for (final chat in list) {
        if (chat.peer != null) {
          final isHidden = await LocalDb.isChatHidden(chat.peer!.id);
          if (!isHidden) {
            await LocalDb.upsertChat(chat);
            filteredList.add(chat);
          }
        } else if (chat.group != null) {
          filteredList.add(chat);
        }
      }

      if (!mounted) return;
      setState(() {
        _chats = filteredList;
        _loading = false;
      });
    } catch (e) {
      logUserActionError('load_chats', e);
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : context.tr('load_error');
        _chats = cached;
        _loading = false;
      });
    }
  }

  String _formatChatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (msgDay == today.subtract(const Duration(days: 1))) {
        return 'вчера';
      } else if (dt.year == now.year) {
        const months = [
          'янв', 'фев', 'мар', 'апр', 'май', 'июн',
          'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
        ];
        return '${dt.day} ${months[dt.month - 1]}';
      } else {
        return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
      }
    } catch (_) {
      return '';
    }
  }

  String _previewContent(BuildContext context, String content) {
    if (content.startsWith('e2ee:')) return context.tr('message');
    return content;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          padding: AppSpacing.navigationPadding,
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  context.tr('chats'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: context.tr('search_in_chats'),
                    onPressed: () => context.push('/search'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: context.tr('new_chat'),
                    onPressed: () async {
                      await context.push('/start-chat');
                      _load();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const AppUpdateBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _chats.isEmpty
                ? ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: 10,
                    itemBuilder: (context, _) =>
                        const Card(child: SkeletonChatTile()),
                  )
                : _error != null && _chats.isEmpty
                ? ErrorStateWidget(
                    message: _error!,
                    onRetry: _load,
                    retryLabel: context.tr('retry'),
                  )
                : _chats.isEmpty
                ? EmptyStateWidget(message: context.tr('no_chats'))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _chats.length,
                    itemBuilder: (context, i) {
                      final c = _chats[i];
                      final isGroup = c.isGroup;
                      final title = isGroup
                          ? c.group!.name
                          : c.peer!.displayName;
                      final avatarUrl = isGroup
                          ? c.group!.avatarUrl
                          : c.peer!.avatarUrl;
                      String subtitleText = '';
                      if (c.lastMessage != null) {
                        if (c.lastMessage!.isMine) {
                          subtitleText =
                              '${context.tr('you_prefix')}${c.lastMessage!.isPoll ? context.tr('poll_prefix') : ''}${_previewContent(context, c.lastMessage!.content)}';
                        } else {
                          final prefix =
                              isGroup &&
                                  c.lastMessage!.senderDisplayName != null
                              ? '${c.lastMessage!.senderDisplayName}: '
                              : '';
                          subtitleText =
                              '$prefix${c.lastMessage!.isPoll ? context.tr('poll_prefix') : ''}${_previewContent(context, c.lastMessage!.content)}';
                        }
                      }
                      final theme = Theme.of(context);
                      final unread = c.unreadCount;
                      Widget avatarWidget = isGroup
                          ? CircleAvatar(
                              radius: 27,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              backgroundImage:
                                  avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? Icon(
                                      Icons.group,
                                      size: 28,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.85),
                                    )
                                  : null,
                            )
                          : UserAvatar(user: c.peer!, radius: 27);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: theme.colorScheme.surface,
                            child: InkWell(
                              onTap: () async {
                                logUserAction('open_chat', {
                                  'type': isGroup ? 'group' : 'dm',
                                  'id': isGroup ? c.group!.id : c.peer!.id,
                                  'name': title,
                                });
                                if (isGroup) {
                                  await context.push('/group/${c.group!.id}');
                                } else {
                                  await context.push('/chat/${c.peer!.id}');
                                }
                                _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    avatarWidget,
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatChatTime(
                                                  c.lastMessage?.createdAt,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: unread > 0
                                                      ? theme.colorScheme.primary
                                                      : theme.colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  subtitleText.isEmpty
                                                      ? ' '
                                                      : subtitleText,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                              if (unread > 0) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 20,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        theme.colorScheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    unread > 99
                                                        ? '99+'
                                                        : '$unread',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Divider(
                            height: 0,
                            thickness: 0.5,
                            indent: 78,
                            color: theme.dividerColor,
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
