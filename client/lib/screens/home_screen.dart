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
import '../widgets/start_chat_content.dart';
import '../widgets/profile_content.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../services/app_update_service.dart';
import '../config/version.dart' show AppVersion;
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NavigationItem {
  chats,
  contacts,
  newChat,
  profile,
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  List<ChatPreview> _chats = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _newMessageSub;
  StreamSubscription<Message>? _newMessagePayloadSub;
  List<FriendRequest> _friendRequests = [];
  int _totalUnreadCount = 0;
  _NavigationItem _currentView = _NavigationItem.chats;

  bool _initialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ws = context.read<WsService>();
        ws.connect(context.read<AuthService>().token);
        
        // Проверяем обновления при возврате на главный экран
        try {
          context.read<AppUpdateService>().checkForUpdates();
        } catch (_) {
          // Игнорируем ошибки проверки обновлений
        }
        
        _load();
        _loadFriendRequests();
        _newMessageSub = ws.onNewMessage.listen((_) {
          if (!mounted) return;
          _load();
          _loadFriendRequests();
        });
        _newMessagePayloadSub = ws.onNewMessageWithPayload.listen((msg) {
          if (!mounted || isPageVisible) return;
          AppSoundService.instance.playNotification();
          requestNotificationPermission();
          final from = msg.isGroupMessage
              ? 'Группа'
              : (msg.senderDisplayName ?? 'Сообщение');
          final preview = msg.content.isEmpty
              ? (msg.hasAttachment ? 'Вложение' : '—')
              : (msg.content.length > 50 ? '${msg.content.substring(0, 50)}…' : msg.content);
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
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Local-first: сразу показываем кэш из локальной БД
    final cached = await LocalDb.getChats();
    if (cached.isNotEmpty && mounted) {
      setState(() => _chats = cached);
    }
    try {
      final api = Api(auth.token);
      final list = await api.getChats();
      if (!mounted) return;
      for (final chat in list) {
        if (chat.peer != null) await LocalDb.upsertChat(chat);
      }
      if (!mounted) return;
      // Подсчитываем общее количество непрочитанных сообщений
      final totalUnread = list.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
      
      setState(() {
        _chats = list;
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
    if (!auth.isLoggedIn) return;
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
    if (items.isNotEmpty && mounted) _load();
  }

  Future<void> _loadFriendRequests() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
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
      case _NavigationItem.newChat:
        return context.tr('new_chat');
      case _NavigationItem.profile:
        return context.tr('profile');
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
        );
      case _NavigationItem.newChat:
        return const StartChatContent();
      case _NavigationItem.profile:
        return const ProfileContent();
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
                    itemBuilder: (_, __) => const Card(child: SkeletonChatTile()),
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
                              final title = isGroup ? (c.group!.name) : (c.peer!.displayName);
                              final avatarUrl = isGroup ? c.group!.avatarUrl : c.peer!.avatarUrl;
                              String subtitleText = '';
                              if (c.lastMessage != null) {
                                if (c.lastMessage!.isMine) {
                                  subtitleText = '${context.tr('you_prefix')}${c.lastMessage!.isPoll ? context.tr('poll_prefix') : ''}${_previewContent(context, c.lastMessage!.content)}';
                                } else {
                                  final prefix = isGroup && c.lastMessage!.senderDisplayName != null
                                      ? '${c.lastMessage!.senderDisplayName}: '
                                      : '';
                                  subtitleText = '$prefix${c.lastMessage!.isPoll ? context.tr('poll_prefix') : ''}${_previewContent(context, c.lastMessage!.content)}';
                                }
                              }
                              return Card(
                                margin: EdgeInsets.only(bottom: AppSpacing.sm),
                                child: ListTile(
                                  contentPadding: AppSpacing.cardPadding,
                                  leading: CircleAvatar(
                                    radius: AppSizes.avatarLG,
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl == null || avatarUrl.isEmpty
                                        ? Icon(
                                            isGroup ? Icons.group : Icons.person,
                                            size: AppSizes.iconXXL,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                                          )
                                        : null,
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
                                      if (unread > 0)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                            vertical: AppSpacing.xs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primary,
                                            borderRadius: BorderRadius.circular(AppSizes.radiusLG),
                                          ),
                                          child: Text(
                                            unread > 99 ? '99+' : '$unread',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onPrimary,
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
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              fontSize: 14,
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return OfflineIndicator(
      child: Scaffold(
            appBar: AppBar(
              title: Text(_getAppBarTitle(context)),
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Левая навигация: профиль, чаты, друзья, новый чат, внизу выход
                Container(
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
                      AppSpacing.spacingVerticalSM,
                      Builder(
                        builder: (context) {
                          return Consumer<AuthService>(
                            builder: (context, auth, _) {
                              final user = auth.user;
                              final isActive = _currentView == _NavigationItem.profile;
                              return IconButton(
                                icon: (user?.avatarUrl != null && user.avatarUrl!.isNotEmpty)
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
                                style: IconButton.styleFrom(
                                  backgroundColor: isActive
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : null,
                                ),
                                onPressed: () {
                                  if (mounted && _currentView != _NavigationItem.profile) {
                                    setState(() {
                                      _currentView = _NavigationItem.profile;
                                    });
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                      IconButton(
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
                                right: -AppSpacing.xs,
                                top: -AppSpacing.xs,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(AppSizes.radiusMD),
                                  ),
                                  child: Text(
                                    _totalUnreadCount > 99 ? '99+' : '$_totalUnreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        tooltip: context.tr('chats'),
                        style: IconButton.styleFrom(
                          backgroundColor: _currentView == _NavigationItem.chats
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                        onPressed: () {
                          if (mounted && _currentView != _NavigationItem.chats) {
                            setState(() {
                              _currentView = _NavigationItem.chats;
                            });
                          }
                        },
                      ),
                      IconButton(
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
                                right: -AppSpacing.xs,
                                top: -AppSpacing.xs,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(AppSizes.radiusMD),
                                  ),
                                  child: Text(
                                    _friendRequests.length > 99 ? '99+' : '${_friendRequests.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        tooltip: context.tr('contacts'),
                        style: IconButton.styleFrom(
                          backgroundColor: _currentView == _NavigationItem.contacts
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                        onPressed: () {
                          if (mounted && _currentView != _NavigationItem.contacts) {
                            setState(() {
                              _currentView = _NavigationItem.contacts;
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          size: AppSizes.iconXL,
                          color: _currentView == _NavigationItem.newChat
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        tooltip: context.tr('new_chat'),
                        style: IconButton.styleFrom(
                          backgroundColor: _currentView == _NavigationItem.newChat
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                        onPressed: () {
                          if (mounted && _currentView != _NavigationItem.newChat) {
                            setState(() {
                              _currentView = _NavigationItem.newChat;
                            });
                          }
                        },
                      ),
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          'v${AppVersion.displayVersion}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: AppSizes.iconXL),
                        tooltip: context.tr('settings'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, size: AppSizes.iconXL),
                        tooltip: context.tr('logout'),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
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
                            await context.read<AuthService>().logout();
                            if (!mounted) return;
                            context.go('/login');
                          }
                        },
                      ),
                      AppSpacing.spacingVerticalSM,
                    ],
                  ),
                ),
                Expanded(
                  child: _buildContentView(context),
                ),
              ],
            ),
      ),
    );
  }
}
