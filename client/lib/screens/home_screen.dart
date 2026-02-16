import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import '../database/local_db.dart';
import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/friend_request.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../services/app_sound_service.dart';
import '../utils/page_visibility.dart';
import '../widgets/skeleton.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/app_update_banner.dart';
import '../widgets/user_avatar.dart';
import '../widgets/contacts_content.dart';
import '../widgets/profile_content.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../services/app_update_service.dart';
import '../services/chat_list_refresh_service.dart';
import '../services/call_minimized_service.dart';
import '../config/version.dart' show AppVersion;
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import '../widgets/nav_badge.dart';
import 'possible_friends_screen.dart';
import 'add_contact_screen.dart';

class HomeScreen extends StatefulWidget {
  final Widget? child;

  const HomeScreen({super.key, this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NavigationItem { chats, contacts, profile }

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<ChatPreview> _chats = [];
  Set<String> _mutedChatKeys = {};
  Map<String, String> _pinnedChats = {};
  bool _loading = true;
  String? _error;
  StreamSubscription? _newMessageSub;
  StreamSubscription<Message>? _newMessagePayloadSub;
  List<FriendRequest> _friendRequests = [];
  int _totalUnreadCount = 0;
  _NavigationItem _currentView = _NavigationItem.chats;

  _NavigationItem _viewFromPath(String path) {
    if (path.startsWith('/contacts')) return _NavigationItem.contacts;
    if (path.startsWith('/profile')) return _NavigationItem.profile;
    return _NavigationItem.chats;
  }

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _initialized = false;

  @override
  bool get wantKeepAlive => true;

  void _onRefreshRequested() {
    if (mounted && _currentView == _NavigationItem.chats) {
      _load();
      _loadFriendRequests();
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = context.read<WsService>();
        ws.connect(context.read<AuthService>().token);

        // Слушаем запросы обновления списка чатов (возврат на главный экран)
        context.read<ChatListRefreshService>().addListener(_onRefreshRequested);

        // Проверяем обновления при возврате на главный экран
        try {
          context.read<AppUpdateService>().checkForUpdates();
        } catch (_) {
          // Игнорируем ошибки проверки обновлений
        }

        _load();
        _loadFriendRequests();
        WidgetsBinding.instance.addObserver(this);
        _newMessageSub = ws.onNewMessage.listen((_) {
          if (!mounted) {
            return;
          }
          _load();
          _loadFriendRequests();
        });
        _newMessagePayloadSub = ws.onNewMessageWithPayload.listen((msg) async {
          if (!mounted || isPageVisible) return;
          final chatKey = msg.isGroupMessage
              ? 'g_${msg.groupId}'
              : 'p_${msg.isMine ? msg.receiverId : msg.senderId}';
          final muted = await LocalDb.getMutedChatKeys();
          if (muted.contains(chatKey)) return;
          AppSoundService.instance.playNotification();
          requestNotificationPermission();
          final from = msg.isGroupMessage
              ? 'Группа'
              : (msg.senderDisplayName ?? 'Сообщение');
          final preview = msg.content.isEmpty
              ? (msg.hasAttachment ? 'Вложение' : '—')
              : (msg.content.length > 50
                    ? '${msg.content.substring(0, 50)}…'
                    : msg.content);
          showPageNotification(
            title: 'Новое сообщение',
            body: '$from: $preview',
          );
        });
      });
      Connectivity().onConnectivityChanged.listen((_) {
        if (!mounted) return;
        _flushOutbox();
      });
    }
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    _newMessagePayloadSub?.cancel();
    if (_initialized) {
      try {
        context.read<ChatListRefreshService>().removeListener(
          _onRefreshRequested,
        );
      } catch (_) {}
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _currentView == _NavigationItem.chats) {
      _load();
      _loadFriendRequests();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Local-first: сразу показываем кэш из локальной БД
    final cached = await LocalDb.getChats();
    final muted = await LocalDb.getMutedChatKeys();
    final pinned = await LocalDb.getPinnedChats();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _chats = _sortChats(cached, pinned);
        _mutedChatKeys = muted;
        _pinnedChats = pinned;
      });
    }
    try {
      final api = Api(auth.token);
      final list = await api.getChats();
      if (!mounted) return;

      final muted = await LocalDb.getMutedChatKeys();
      final pinned = await LocalDb.getPinnedChats();
      // Фильтруем скрытые чаты
      final filteredList = <ChatPreview>[];
      for (final chat in list) {
        if (chat.peer != null) {
          final isHidden = await LocalDb.isChatHidden(chat.peer!.id);
          if (!isHidden) {
            await LocalDb.upsertChat(chat);
            filteredList.add(chat);
          }
        } else if (chat.group != null) {
          // Групповые чаты не скрываем пока
          filteredList.add(chat);
        }
      }

      if (!mounted) return;
      // Подсчитываем общее количество непрочитанных сообщений
      final totalUnread = filteredList.fold<int>(
        0,
        (sum, chat) => sum + chat.unreadCount,
      );

      setState(() {
        _chats = _sortChats(filteredList, pinned);
        _mutedChatKeys = muted;
        _pinnedChats = pinned;
        _loading = false;
        _totalUnreadCount = totalUnread;
      });
      _flushOutbox();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : context.tr('load_error');
        _loading = false;
        _chats = cached;
      });
    }
  }

  Future<void> _flushOutbox() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    final items = await LocalDb.getOutbox();
    if (items.isEmpty) return;
    final api = Api(auth.token);
    for (final item in items) {
      try {
        final msg = await api.sendMessage(item.peerId, item.content);
        await LocalDb.removeFromOutbox(item.id);
        await LocalDb.upsertMessage(msg, item.peerId);
        await LocalDb.updateChatLastMessage(item.peerId, msg);
      } catch (_) {}
    }
    if (items.isNotEmpty && mounted) {
      _load();
    }
  }

  Future<void> _loadFriendRequests() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    try {
      final api = Api(auth.token);
      final requests = await api.getFriendRequestsIncoming();
      if (mounted) {
        setState(() {
          _friendRequests = requests;
        });
      }
    } catch (_) {
      // Игнорируем ошибки загрузки заявок
    }
  }

  Future<void> _confirmDeleteChat(
    BuildContext context,
    ChatPreview chat,
    bool isGroup,
  ) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final title = isGroup ? (chat.group!.name) : (chat.peer!.displayName);

    final ok = await showDialog<bool>(
      context: navigator.context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_chat_title')),
        content: Text(
          context.tr('delete_chat_message').replaceFirst('%s', title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        if (isGroup) {
          // Для групповых чатов просто удаляем из текущего списка
          // Групповые чаты не сохраняются в локальную БД, поэтому они вернутся
          // при следующей загрузке, если пользователь все еще в группе
          setState(() {
            _chats.removeWhere(
              (c) => c.isGroup && c.group?.id == chat.group?.id,
            );
          });
        } else {
          // Для приватных чатов удаляем из локальной БД и обновляем список
          await LocalDb.deleteChat(chat.peer!.id);
          if (mounted) {
            setState(() {
              _chats.removeWhere(
                (c) => !c.isGroup && c.peer?.id == chat.peer?.id,
              );
            });
          }
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        final currentContext = context;
        final errorMessage = e is ApiException
            ? e.message
            : currentContext.tr('error');
        if (!mounted) {
          return;
        }
        final scaffoldMessenger = ScaffoldMessenger.of(currentContext);
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  List<ChatPreview> _sortChats(List<ChatPreview> chats, Map<String, String> pinned) {
    if (pinned.isEmpty) {
      return chats;
    }
    final pinnedKeys = pinned.keys.toSet();
    final pinnedList = <ChatPreview>[];
    final unpinnedList = <ChatPreview>[];
    for (final c in chats) {
      final key = c.isGroup ? 'g_${c.group!.id}' : 'p_${c.peer!.id}';
      if (pinnedKeys.contains(key)) {
        pinnedList.add(c);
      } else {
        unpinnedList.add(c);
      }
    }
    pinnedList.sort((a, b) {
      final keyA = a.isGroup ? 'g_${a.group!.id}' : 'p_${a.peer!.id}';
      final keyB = b.isGroup ? 'g_${b.group!.id}' : 'p_${b.peer!.id}';
      final atA = pinned[keyA] ?? '';
      final atB = pinned[keyB] ?? '';
      return atB.compareTo(atA);
    });
    unpinnedList.sort((a, b) {
      final atA = a.lastMessage?.createdAt ?? '';
      final atB = b.lastMessage?.createdAt ?? '';
      return atB.compareTo(atA);
    });
    return [...pinnedList, ...unpinnedList];
  }

  String _previewContent(BuildContext context, String content) {
    if (content.startsWith('e2ee:')) return context.tr('message');
    return content;
  }

  String _getAppBarTitle(BuildContext context) {
    switch (_currentView) {
      case _NavigationItem.chats:
        return context.tr('chats');
      case _NavigationItem.contacts:
        return context.tr('contacts');
      case _NavigationItem.profile:
        return context.tr('profile');
    }
  }

  List<Widget> _appBarActionsForMobile(BuildContext context, bool isMobile) {
    if (!isMobile) return [];
    switch (_currentView) {
      case _NavigationItem.chats:
        return [
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
        ];
      case _NavigationItem.contacts:
        return [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: context.tr('possible_friends'),
            onPressed: () async {
              final nav = _navigatorKey.currentState ?? Navigator.of(context);
              await nav.push(
                MaterialPageRoute(builder: (_) => const PossibleFriendsScreen()),
              );
              _loadFriendRequests();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('add_by_username'),
            onPressed: () async {
              final nav = _navigatorKey.currentState ?? Navigator.of(context);
              await nav.push(
                MaterialPageRoute(builder: (_) => const AddContactScreen()),
              );
              _loadFriendRequests();
            },
          ),
        ];
      case _NavigationItem.profile:
        return [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: context.tr('settings'),
            onPressed: () => context.push('/settings'),
          ),
        ];
    }
  }

  Widget _buildContentView(BuildContext context) {
    switch (_currentView) {
      case _NavigationItem.chats:
        return _buildChatsView(context);
      case _NavigationItem.contacts:
        return ContactsContent(
          onFriendRequestChanged: () {
            _loadFriendRequests();
          },
          navigator: _navigatorKey.currentState,
        );
      case _NavigationItem.profile:
        return ProfileContent(navigator: _navigatorKey.currentState);
    }
  }

  Widget _buildChatsView(BuildContext context) {
    return Column(
      children: [
        const AppUpdateBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _chats.isEmpty
                ? ListView.builder(
                    padding: AppSpacing.listPadding,
                    itemCount: 10,
                    itemBuilder: (_, _) =>
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
                      final unread = c.unreadCount;
                      final isGroup = c.isGroup;
                      final title = isGroup
                          ? (c.group!.name)
                          : (c.peer!.displayName);
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
                                  radius: AppSizes.avatarLG,
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
                                          size: AppSizes.iconXXL,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                              .withValues(alpha: 0.7),
                                        )
                                      : null,
                                )
                              : Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: AppSizes.avatarLG,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      backgroundImage:
                                          avatarUrl != null &&
                                              avatarUrl.isNotEmpty
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                      child:
                                          avatarUrl == null || avatarUrl.isEmpty
                                          ? Icon(
                                              Icons.person,
                                              size: AppSizes.iconXXL,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer
                                                  .withValues(alpha: 0.7),
                                            )
                                          : null,
                                    ),
                                    if (c.peer?.isOnline == true)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surface,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_pinnedChats.containsKey(isGroup ? 'g_${c.group!.id}' : 'p_${c.peer!.id}'))
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (_mutedChatKeys.contains(isGroup ? 'g_${c.group!.id}' : 'p_${c.peer!.id}'))
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.notifications_off,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (unread > 0)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.radiusLG,
                                    ),
                                  ),
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: c.lastMessage != null
                              ? Padding(
                                  padding: EdgeInsets.only(top: AppSpacing.xs),
                                  child: Text(
                                    subtitleText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              : null,
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: AppSizes.iconSM,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onSelected: (value) async {
                              final key = isGroup ? 'g_${c.group!.id}' : 'p_${c.peer!.id}';
                              if (value == 'mute') {
                                await LocalDb.setChatMuted(
                                  peerId: isGroup ? null : c.peer!.id,
                                  groupId: isGroup ? c.group!.id : null,
                                  muted: true,
                                );
                                if (mounted) setState(() => _mutedChatKeys = {..._mutedChatKeys, key});
                              } else if (value == 'unmute') {
                                await LocalDb.setChatMuted(
                                  peerId: isGroup ? null : c.peer!.id,
                                  groupId: isGroup ? c.group!.id : null,
                                  muted: false,
                                );
                                if (mounted) setState(() => _mutedChatKeys = {..._mutedChatKeys}..remove(key));
                              } else if (value == 'pin') {
                                await LocalDb.setChatPinned(
                                  peerId: isGroup ? null : c.peer!.id,
                                  groupId: isGroup ? c.group!.id : null,
                                  pinned: true,
                                );
                                if (mounted) setState(() {
                                  _pinnedChats = {..._pinnedChats, key: DateTime.now().toIso8601String()};
                                  _chats = _sortChats(List.from(_chats), _pinnedChats);
                                });
                              } else if (value == 'unpin') {
                                await LocalDb.setChatPinned(
                                  peerId: isGroup ? null : c.peer!.id,
                                  groupId: isGroup ? c.group!.id : null,
                                  pinned: false,
                                );
                                if (mounted) setState(() {
                                  _pinnedChats = Map.from(_pinnedChats)..remove(key);
                                  _chats = _sortChats(List.from(_chats), _pinnedChats);
                                });
                              } else if (value == 'delete') {
                                _confirmDeleteChat(context, c, isGroup);
                              }
                            },
                            itemBuilder: (ctx) {
                              final chatKey = isGroup ? 'g_${c.group!.id}' : 'p_${c.peer!.id}';
                              final isMuted = _mutedChatKeys.contains(chatKey);
                              final isPinned = _pinnedChats.containsKey(chatKey);
                              return [
                                PopupMenuItem(
                                  value: isPinned ? 'unpin' : 'pin',
                                  child: Row(
                                    children: [
                                      Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
                                      const SizedBox(width: 12),
                                      Text(isPinned ? context.tr('unpin_chat') : context.tr('pin_chat')),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: isMuted ? 'unmute' : 'mute',
                                  child: Row(
                                    children: [
                                      Icon(isMuted ? Icons.notifications : Icons.notifications_off, size: 20),
                                      const SizedBox(width: 12),
                                      Text(isMuted ? context.tr('unmute_chat') : context.tr('mute_chat')),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                                      const SizedBox(width: 12),
                                      Text(
                                        context.tr('delete_chat'),
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
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

  bool get _isMainRoute {
    final path = GoRouterState.of(context).uri.path;
    return path == '/' ||
        path.startsWith('/contacts') ||
        path.startsWith('/profile');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    _currentView = _viewFromPath(GoRouterState.of(context).uri.path);
    final content = _isMainRoute ? _buildContentView(context) : widget.child!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = AppSizes.isMobile(screenWidth);

    return OfflineIndicator(
      child: Scaffold(
        appBar: _isMainRoute
            ? AppBar(
                title: Text(_getAppBarTitle(context)),
                actions: [
                  if (isMobile) ..._appBarActionsForMobile(context, isMobile),
                  if (isMobile)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'settings') {
                          context.push('/settings');
                        } else if (value == 'logout') {
                          final navigator = _navigatorKey.currentState;
                          if (navigator == null) return;
                          final ok = await showDialog<bool>(
                            context: navigator.context,
                            useRootNavigator: false,
                            builder: (ctx) => AlertDialog(
                              title: Text(context.tr('logout_confirm')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(context.tr('cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(context.tr('logout')),
                                ),
                              ],
                            ),
                          );
                          if (ok == true && mounted) {
                            final authService = context.read<AuthService>();
                            await authService.logout();
                            if (mounted) context.go('/login');
                          }
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              const Icon(Icons.settings, size: 20),
                              const SizedBox(width: 12),
                              Text(context.tr('settings')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(
                                Icons.logout,
                                size: 20,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                context.tr('logout'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              )
            : null,
        body: isMobile
            ? SafeArea(
                child: _isMainRoute
                    ? Navigator(
                        key: _navigatorKey,
                        onGenerateRoute: (settings) => MaterialPageRoute(
                          builder: (_) => _buildContentView(context),
                          settings: settings,
                        ),
                      )
                    : content,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSideNav(context),
                  Expanded(
                    child: _isMainRoute
                        ? Navigator(
                            key: _navigatorKey,
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              builder: (_) => _buildContentView(context),
                              settings: settings,
                            ),
                          )
                        : content,
                  ),
                ],
              ),
        bottomNavigationBar: isMobile ? _buildBottomNav(context) : null,
      ),
    );
  }

  Widget _buildSideNav(BuildContext context) {
    return Container(
      width: AppSizes.navigationWidth,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Профиль
                  Builder(
                    builder: (context) {
                      return Consumer<AuthService>(
                        builder: (context, auth, _) {
                          final user = auth.user;
                          final isActive =
                              _currentView == _NavigationItem.profile;
                          return _NavButton(
                            icon:
                                (user != null &&
                                    (user.avatarUrl?.isNotEmpty ?? false))
                                ? UserAvatar(
                                    user: user,
                                    radius: AppSizes.avatarSM,
                                  )
                                : Icon(
                                    Icons.account_circle_outlined,
                                    size: AppSizes.iconXL,
                                    color: isActive
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                            tooltip: context.tr('my_profile'),
                            isActive: isActive,
                            onPressed: () {
                              if (mounted &&
                                  _currentView != _NavigationItem.profile) {
                                context.go('/profile');
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Чаты с badge
                  _NavButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.chat_outlined,
                          size: AppSizes.iconXL,
                          color: _currentView == _NavigationItem.chats
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        if (_totalUnreadCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: NavBadge(count: _totalUnreadCount),
                          ),
                      ],
                    ),
                    tooltip: context.tr('chats'),
                    isActive: _currentView == _NavigationItem.chats,
                    onPressed: () {
                      if (mounted && _currentView != _NavigationItem.chats) {
                        context.go('/');
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Контакты с badge
                  _NavButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: AppSizes.iconXL,
                          color: _currentView == _NavigationItem.contacts
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        if (_friendRequests.isNotEmpty)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: NavBadge(count: _friendRequests.length),
                          ),
                      ],
                    ),
                    tooltip: context.tr('contacts'),
                    isActive: _currentView == _NavigationItem.contacts,
                    onPressed: () {
                      if (mounted && _currentView != _NavigationItem.contacts) {
                        context.go('/contacts');
                      }
                    },
                  ),
                  const Spacer(),
                  // Разделитель перед нижними кнопками
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    height: 1,
                    width: 40,
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.3),
                  ),
                  // Версия
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'v${AppVersion.displayVersion}',
                      style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Настройки
                  _NavButton(
                    icon: const Icon(Icons.settings, size: AppSizes.iconXL),
                    tooltip: context.tr('settings'),
                    isActive: false,
                    onPressed: () => context.push('/settings'),
                  ),
                  const SizedBox(height: 4),
                  // Выход
                  _NavButton(
                    icon: Icon(
                      Icons.logout,
                      size: AppSizes.iconXL,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: context.tr('logout'),
                    isActive: false,
                    onPressed: () async {
                      final navigator = _navigatorKey.currentState;
                      if (navigator == null) {
                        return;
                      }
                      final ok = await showDialog<bool>(
                        context: navigator.context,
                        useRootNavigator: false,
                        builder: (ctx) => AlertDialog(
                          title: Text(context.tr('logout_confirm')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(context.tr('cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(context.tr('logout')),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        if (!mounted) {
                          return;
                        }
                        final currentContext = context;
                        final authService = currentContext.read<AuthService>();
                        final router = currentContext;
                        await authService.logout();
                        if (!mounted) {
                          return;
                        }
                        router.go('/login');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
  }

  void _onTabTap(String path, _NavigationItem target) {
    if (!mounted || _currentView == target) return;
    final minimizedService = context.read<CallMinimizedService>();
    if (minimizedService.hasActiveCall && minimizedService.peer != null) {
      minimizedService.minimizeCall(minimizedService.peer!, minimizedService.isVideoCall);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    context.go(path);
  }

  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: AppSizes.bottomNavHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.account_circle_outlined,
                label: context.tr('my_profile'),
                isActive: _currentView == _NavigationItem.profile,
                onTap: () => _onTabTap('/profile', _NavigationItem.profile),
              ),
              _BottomNavItem(
                icon: Icons.chat_outlined,
                label: context.tr('chats'),
                isActive: _currentView == _NavigationItem.chats,
                badge: _totalUnreadCount > 0 ? _totalUnreadCount : null,
                onTap: () => _onTabTap('/', _NavigationItem.chats),
              ),
              _BottomNavItem(
                icon: Icons.people_outline,
                label: context.tr('contacts'),
                isActive: _currentView == _NavigationItem.contacts,
                badge: _friendRequests.isNotEmpty ? _friendRequests.length : null,
                onTap: () => _onTabTap('/contacts', _NavigationItem.contacts),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  if (badge != null && badge! > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: NavBadge(count: badge!),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Аккуратная кнопка навигации с улучшенным стилем
class _NavButton extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
