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
import '../widgets/nav_badge.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NavigationItem { chats, contacts, newChat, profile }

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  List<ChatPreview> _chats = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _newMessageSub;
  StreamSubscription<Message>? _newMessagePayloadSub;
  List<FriendRequest> _friendRequests = [];
  int _totalUnreadCount = 0;
  _NavigationItem _currentView = _NavigationItem.chats;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
          if (!mounted) {
            return;
          }
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
    super.dispose();
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
    if (cached.isNotEmpty && mounted) {
      setState(() => _chats = cached);
    }
    try {
      final api = Api(auth.token);
      final list = await api.getChats();
      if (!mounted) return;

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
        _chats = filteredList;
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
        final errorMessage = e is ApiException
            ? e.message
            : context.tr('error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
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
          navigator: _navigatorKey.currentState,
        );
      case _NavigationItem.newChat:
        return StartChatContent(navigator: _navigatorKey.currentState);
      case _NavigationItem.profile:
        return ProfileContent(navigator: _navigatorKey.currentState);
    }
  }

  Widget _buildChatsView(BuildContext context) {
    return Column(
      children: [
        // Заголовок
        Container(
          padding: AppSpacing.navigationPadding,
          height: AppSizes.appBarHeight,
          child: Row(
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
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: AppSizes.iconSM,
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.7),
                            ),
                            tooltip: context.tr('delete_chat'),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () =>
                                _confirmDeleteChat(context, c, isGroup),
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return OfflineIndicator(
      child: Scaffold(
        appBar: AppBar(title: Text(_getAppBarTitle(context))),
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
                        setState(() {
                          _currentView = _NavigationItem.chats;
                        });
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
                        setState(() {
                          _currentView = _NavigationItem.contacts;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Новый чат
                  _NavButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: AppSizes.iconXL,
                      color: _currentView == _NavigationItem.newChat
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    tooltip: context.tr('new_chat'),
                    isActive: _currentView == _NavigationItem.newChat,
                    onPressed: () {
                      if (mounted && _currentView != _NavigationItem.newChat) {
                        setState(() {
                          _currentView = _NavigationItem.newChat;
                        });
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
                    onPressed: () {
                      final nav =
                          _navigatorKey.currentState ?? Navigator.of(context);
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            navigator: _navigatorKey.currentState,
                          ),
                        ),
                      );
                    },
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
                        final navigator = context;
                        await navigator.read<AuthService>().logout();
                        if (!mounted) {
                          return;
                        }
                        navigator.go('/login');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: Navigator(
                key: _navigatorKey,
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(
                    builder: (context) => _buildContentView(context),
                    settings: settings,
                  );
                },
              ),
            ),
          ],
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
