import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../utils/app_page_route.dart';
import '../widgets/app_back_button.dart';
import 'group_profile_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final Group group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<Message> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Message? _replyingTo;
  VoidCallback? _wsUnsub;

  @override
  void initState() {
    super.initState();
    _load();
    final ws = context.read<WsService>();
    void onUpdate() {
      if (!mounted) {
        return;
      }
      _drainIncoming(ws);
    }

    _wsUnsub = () => ws.removeListener(onUpdate);
    ws.addListener(onUpdate);
    _drainIncoming(ws);
  }

  @override
  void dispose() {
    _wsUnsub?.call();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static const List<String> _reactionEmojis = [
    '👍',
    '👎',
    '❤️',
    '🔥',
    '😂',
    '😮',
    '😢',
  ];

  Future<void> _drainIncoming(WsService ws) async {
    Message? m;
    while ((m = ws.takeIncomingGroupFor(widget.group.id)) != null) {
      if (!mounted) {
        return;
      }
      setState(() => _messages.add(m!));
    }
    ReactionUpdate? ru;
    while ((ru = ws.takeGroupReactionUpdateFor(widget.group.id)) != null) {
      final idx = _messages.indexWhere((msg) => msg.id == ru!.messageId);
      if (idx >= 0 && mounted) {
        setState(
          () => _messages[idx] = _messages[idx].copyWith(
            reactions: ru!.reactions,
          ),
        );
      }
    }
  }

  Future<void> _setGroupReaction(Message m, String emoji) async {
    try {
      final reactions = await Api(
        context.read<AuthService>().token,
      ).setGroupMessageReaction(widget.group.id, m.id, emoji);
      if (!mounted) {
        return;
      }
      final idx = _messages.indexWhere((msg) => msg.id == m.id);
      if (idx >= 0) {
        setState(
          () => _messages[idx] = _messages[idx].copyWith(reactions: reactions),
        );
      }
    } catch (_) {}
  }

  List<Widget> _reactionAvatars(BuildContext context, MessageReaction r) {
    final members = widget.group.members;
    final theme = Theme.of(context);
    return r.userIds.take(3).map((userId) {
      String? avatarUrl;
      String initial = '?';
      if (members != null) {
        GroupMember? member;
        for (final m in members) {
          if (m.id == userId) {
            member = m;
            break;
          }
        }
        if (member != null) {
          avatarUrl = member.avatarUrl;
          initial = member.displayName.isNotEmpty
              ? member.displayName[0].toUpperCase()
              : (member.username.isNotEmpty
                    ? member.username[0].toUpperCase()
                    : '?');
        }
      }
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: CircleAvatar(
          radius: 8,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  initial,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
      );
    }).toList();
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
    try {
      final list = await Api(auth.token).getGroupMessages(widget.group.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = list;
        _loading = false;
      });
      if (list.isNotEmpty) {
        await Api(
          auth.token,
        ).markGroupMessagesRead(widget.group.id, list.last.id);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('load_error');
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  static const int _maxMultipleFiles = 10;

  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final files = result.files
        .where((f) => f.bytes != null && f.bytes!.isNotEmpty)
        .take(_maxMultipleFiles)
        .toList();
    if (files.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    if (!mounted) return;
    try {
      final api = Api(context.read<AuthService>().token);
      if (files.length == 1) {
        final file = files.single;
        final msg = await api.sendGroupMessageWithFile(
          widget.group.id,
          '',
          file.bytes!.toList(),
          file.name,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _messages.add(msg);
          _sending = false;
        });
      } else {
        final list = files
            .map((f) => (bytes: f.bytes!.toList(), filename: f.name))
            .toList();
        final messages = await api.sendGroupMessageWithMultipleFiles(
          widget.group.id,
          '',
          list,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _messages.addAll(messages);
          _sending = false;
        });
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : context.tr('error')),
        ),
      );
    }
  }

  Future<void> _sendText() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) {
      return;
    }
    final replyToId = _replyingTo?.id;
    setState(() {
      _sending = true;
      _replyingTo = null;
      _text.clear();
    });
    try {
      final msg = await Api(
        context.read<AuthService>().token,
      ).sendGroupMessage(widget.group.id, content, replyToId: replyToId);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
      await Api(
        context.read<AuthService>().token,
      ).markGroupMessagesRead(widget.group.id, msg.id);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : context.tr('error')),
        ),
      );
    }
  }

  void _onReply(Message m) {
    setState(() => _replyingTo = m);
  }

  String _senderName(Message m) {
    if (m.isMine) {
      return context.tr('you_prefix').trim();
    }
    return m.senderDisplayName ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: GestureDetector(
          onTap: () {
            Navigator.of(context)
                .push(
                  AppPageRoute(
                    builder: (_) => GroupProfileScreen(group: widget.group),
                  ),
                )
                .then((_) {
                  if (mounted) {
                    _load();
                  }
                });
          },
          child: Row(
            children: [
              Expanded(
                child: Text(widget.group.name, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.reply,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _senderName(_replyingTo!),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Text(
                          _replyingTo!.content.length > 60
                              ? '${_replyingTo!.content.substring(0, 57)}...'
                              : _replyingTo!.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
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
                        FilledButton(
                          onPressed: _load,
                          child: Text(context.tr('retry')),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return _buildMessageBubble(m);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Фото или файл',
                  onPressed: _sending ? null : _sendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: InputDecoration(
                      hintText: 'Сообщение',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    enableInteractiveSelection: true,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Отправить',
                  onPressed: _sending ? null : _sendText,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message m) {
    final isMine = m.isMine;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: align,
            children: [
              if (!m.isMine)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text(
                    m.senderDisplayName ?? '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isMine
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: align,
                  children: [
                    if (m.replyToId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.replyToSenderName != null)
                                Text(
                                  m.replyToSenderName!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              Text(
                                m.replyToContent ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    GestureDetector(
                      onLongPress: () => _showGroupMessageActions(m),
                      onSecondaryTapDown: (details) =>
                          _showGroupMessageActions(m, details.globalPosition),
                      child: _buildGroupMessageContent(m),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGroupMessageActions(Message m, [Offset? position]) {
    void openSheet() {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _reactionEmojis.map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _setGroupReaction(m, emoji);
                      },
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(context.tr('reply')),
                onTap: () {
                  Navigator.pop(ctx);
                  _onReply(m);
                },
              ),
            ],
          ),
        ),
      );
    }

    if (position != null) {
      final screen = MediaQuery.sizeOf(context);
      showMenu<void>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          screen.width - position.dx,
          screen.height - position.dy,
        ),
        items: [
          PopupMenuItem(
            onTap: () {
              if (!mounted) {
                return;
              }
              openSheet();
            },
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.emoji_emotions_outlined),
              title: Text('Реакция'),
            ),
          ),
          PopupMenuItem(
            onTap: () {
              if (!mounted) {
                return;
              }
              _onReply(m);
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.reply),
              title: Text(context.tr('reply')),
            ),
          ),
        ],
      );
    } else {
      openSheet();
    }
  }

  Widget _buildGroupMessageContent(Message m) {
    final align = m.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(m.content, style: Theme.of(context).textTheme.bodyLarge),
        if (m.reactions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: m.reactions.map((r) {
              final myId = context.read<AuthService>().user?.id;
              final hasMine = myId != null && r.userIds.contains(myId);
              return InkWell(
                onTap: () {
                  if (hasMine) {
                    _setGroupReaction(m, r.emoji);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._reactionAvatars(context, r),
                      const SizedBox(width: 4),
                      Text(
                        '${r.emoji} ${r.count > 1 ? r.count : ''}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        Text(
          m.createdAt.length > 19 ? m.createdAt.substring(11, 16) : m.createdAt,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
