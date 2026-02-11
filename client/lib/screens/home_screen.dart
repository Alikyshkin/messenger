import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/local_db.dart';
import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../services/app_sound_service.dart';
import '../utils/app_page_route.dart';
import '../utils/page_visibility.dart';
import '../widgets/skeleton.dart';
import '../widgets/offline_indicator.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';
import 'profile_screen.dart';
import 'start_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChatPreview> _chats = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _newMessageSub;
  StreamSubscription<Message>? _newMessagePayloadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = context.read<WsService>();
      ws.connect(context.read<AuthService>().token);
      _load();
      _newMessageSub = ws.onNewMessage.listen((_) {
        if (!mounted) return;
        _load();
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
      setState(() {
        _chats = list;
        _loading = false;
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

  String _previewContent(BuildContext context, String content) {
    if (content.startsWith('e2ee:')) return context.tr('message');
    return content;
  }

  @override
  Widget build(BuildContext context) {
    return OfflineIndicator(
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr('chats')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.tr('new_chat'),
              onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => const StartChatScreen()),
              ).then((_) => _load());
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: context.tr('new_group'),
              onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => const CreateGroupScreen()),
              ).then((_) => _load());
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: context.tr('contacts'),
              onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => const ContactsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: context.tr('my_profile'),
              onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _chats.isEmpty
            ? ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: 10,
                itemBuilder: (_, __) => const Card(child: SkeletonChatTile()),
              )
            : _error != null && _chats.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh, size: 20),
                            label: Text(context.tr('retry')),
                          ),
                        ],
                      ),
                    ),
                  )
                : _chats.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            context.tr('no_chats'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
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
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? Icon(
                                        isGroup ? Icons.group : Icons.person,
                                        size: 32,
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
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
                                      padding: const EdgeInsets.only(top: 4),
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
                                  await Navigator.of(context).push(
                                    AppPageRoute(builder: (_) => GroupChatScreen(group: c.group!)),
                                  );
                                } else {
                                  await Navigator.of(context).push(
                                    AppPageRoute(builder: (_) => ChatScreen(peer: c.peer!)),
                                  );
                                }
                                _load();
                              },
                            ),
                          );
                        },
                      ),
      ),
      ),
    );
  }
}
