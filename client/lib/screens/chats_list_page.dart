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
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : context.tr('load_error');
        _chats = cached;
        _loading = false;
      });
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
                    padding: AppSpacing.listPadding,
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
                    padding: AppSpacing.listPadding,
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
                      return Card(
                        margin: EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ListTile(
                          contentPadding: AppSpacing.cardPadding,
                          leading: isGroup
                              ? CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  backgroundImage:
                                      avatarUrl != null && avatarUrl.isNotEmpty
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? Icon(
                                          Icons.group,
                                          size: 32,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                              .withValues(alpha: 0.7),
                                        )
                                      : null,
                                )
                              : UserAvatar(user: c.peer!, radius: 28),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: c.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            subtitleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: c.unreadCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${c.unreadCount}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () async {
                            if (isGroup) {
                              await context.push('/group/${c.group!.id}');
                            } else {
                              await context.push('/chat/${c.peer!.id}');
                            }
                            _load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
