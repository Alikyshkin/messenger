import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/local_db.dart';
import '../l10n/app_localizations.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/chat_list_refresh_service.dart';
import '../services/attachment_cache.dart';
import '../services/e2ee_service.dart';
import '../services/ws_service.dart';
import '../utils/app_page_route.dart';
import '../utils/format_last_seen.dart';
import 'dart:async';
import '../utils/error_utils.dart';
import '../utils/download_file.dart';
import '../styles/app_sizes.dart';
import '../utils/voice_file_io.dart';
import '../widgets/app_back_button.dart';
import '../widgets/skeleton.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/video_note_bubble.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'record_video_note_screen.dart';
import 'user_profile_screen.dart';
import 'image_preview_screen.dart';
import '../utils/user_action_logger.dart';

class ChatScreen extends StatefulWidget {
  final User peer;

  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();
  final AudioRecorder _audioRecorder = AudioRecorder();
  List<Message> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _isRecording = false;
  String? _recordPath;
  WsService? _ws;
  VoidCallback? _wsUnsub;
  final E2EEService _e2ee = E2EEService();
  Message? _replyingTo;
  PendingAttachment? _pendingAttachment;
  List<PendingFile>? _pendingMultipleFiles;
  final Map<String, Future<Uint8List?>> _attachmentFutureCache = {};
  Timer? _typingDebounce;
  DateTime _lastTypingSent = DateTime(0);

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _load();
    final ws = context.read<WsService>();
    _ws = ws;
    void onUpdate() {
      if (!mounted) {
        return;
      }
      _drainIncoming(ws);
      setState(() {});
    }

    _wsUnsub = () => ws.removeListener(onUpdate);
    ws.addListener(onUpdate);
    _drainIncoming(ws);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
    if (_text.text.trim().isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final ws = _ws;
      if (ws != null && DateTime.now().difference(_lastTypingSent).inSeconds >= 2) {
        ws.sendTyping(widget.peer.id);
        _lastTypingSent = DateTime.now();
      }
    });
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
    final myId = context.read<AuthService>().user?.id;
    Message? m;
    while ((m = ws.takeIncomingFor(widget.peer.id)) != null) {
      Message decrypted = await _decryptMessage(m!, myId: myId);
      if (myId != null && decrypted.isMine != (decrypted.senderId == myId)) {
        decrypted = Message(
          id: decrypted.id,
          senderId: decrypted.senderId,
          receiverId: decrypted.receiverId,
          content: decrypted.content,
          createdAt: decrypted.createdAt,
          readAt: decrypted.readAt,
          isMine: decrypted.senderId == myId,
          attachmentUrl: decrypted.attachmentUrl,
          attachmentFilename: decrypted.attachmentFilename,
          messageType: decrypted.messageType,
          pollId: decrypted.pollId,
          poll: decrypted.poll,
          attachmentKind: decrypted.attachmentKind,
          attachmentDurationSec: decrypted.attachmentDurationSec,
          senderPublicKey: decrypted.senderPublicKey,
          attachmentEncrypted: decrypted.attachmentEncrypted,
          replyToId: decrypted.replyToId,
          replyToContent: decrypted.replyToContent,
          replyToSenderName: decrypted.replyToSenderName,
          isForwarded: decrypted.isForwarded,
          forwardFromSenderId: decrypted.forwardFromSenderId,
          forwardFromDisplayName: decrypted.forwardFromDisplayName,
          reactions: decrypted.reactions,
        );
      }
      await LocalDb.upsertMessage(decrypted, widget.peer.id);
      await LocalDb.updateChatLastMessage(widget.peer.id, decrypted);
      if (!mounted) {
        return;
      }
      final wasAtBottom = _isAtBottom();
      setState(() => _messages.add(decrypted));
      // Прокручиваем к новому сообщению только если пользователь был внизу
      if (wasAtBottom) {
        _scrollToBottom(force: true);
      }
    }
    ReactionUpdate? ru;
    while ((ru = ws.takeReactionUpdateFor(widget.peer.id)) != null) {
      final idx = _messages.indexWhere((msg) => msg.id == ru!.messageId);
      if (idx >= 0 && mounted) {
        setState(
          () => _messages[idx] = _messages[idx].copyWith(
            reactions: ru!.reactions,
          ),
        );
      }
    }
    EditMessageUpdate? eu;
    while ((eu = ws.takeEditUpdateFor(widget.peer.id)) != null) {
      final idx = _messages.indexWhere((msg) => msg.id == eu!.messageId);
      if (idx >= 0 && mounted) {
        setState(
          () => _messages[idx] = _messages[idx].copyWith(
            content: eu!.content,
          ),
        );
      }
    }
    DeleteMessageUpdate? du;
    while ((du = ws.takeDeleteUpdateFor(widget.peer.id)) != null) {
      final idx = _messages.indexWhere((msg) => msg.id == du!.messageId);
      if (idx >= 0 && mounted) {
        await LocalDb.deleteMessage(peerId: widget.peer.id, messageId: du!.messageId);
        setState(() => _messages.removeAt(idx));
      }
    }
    // Пользователь в чате — помечаем все сообщения прочитанными, чтобы при выходе не показывался счётчик непрочитанных
    if (mounted) {
      final auth = context.read<AuthService>();
      Api(auth.token).markMessagesRead(widget.peer.id).catchError((_) {});
    }
  }

  Future<Message> _decryptMessage(Message m, {int? myId}) async {
    if (!m.content.startsWith('e2ee:')) return m;
    // Для своих сообщений используем публичный ключ получателя (peer),
    // потому что сообщение было зашифровано для него.
    // Для входящих сообщений используем sender_public_key (ключ на момент отправки).
    // Fallback: если sender_public_key нет (старые сообщения), пробуем peer.publicKey.
    String? keyToUse;
    if (myId != null && m.senderId == myId) {
      keyToUse = widget.peer.publicKey;
    } else {
      keyToUse = m.senderPublicKey ?? widget.peer.publicKey;
    }
    if (keyToUse == null || keyToUse.isEmpty) {
      return m;
    }
    final decrypted = await _e2ee.decrypt(m.content, keyToUse);
    if (decrypted == null) {
      return m;
    }
    return Message(
      id: m.id,
      senderId: m.senderId,
      receiverId: m.receiverId,
      content: decrypted,
      createdAt: m.createdAt,
      readAt: m.readAt,
      isMine: m.isMine,
      attachmentUrl: m.attachmentUrl,
      attachmentFilename: m.attachmentFilename,
      messageType: m.messageType,
      pollId: m.pollId,
      poll: m.poll,
      attachmentKind: m.attachmentKind,
      attachmentDurationSec: m.attachmentDurationSec,
      senderPublicKey: m.senderPublicKey,
      attachmentEncrypted: m.attachmentEncrypted,
      replyToId: m.replyToId,
      replyToContent: m.replyToContent,
      replyToSenderName: m.replyToSenderName,
      isForwarded: m.isForwarded,
      forwardFromSenderId: m.forwardFromSenderId,
      forwardFromDisplayName: m.forwardFromDisplayName,
      reactions: m.reactions,
    );
  }

  /// Скачивает вложение (из кэша или сети), при необходимости распаковывает и расшифровывает (E2EE).
  Future<Uint8List?> _getAttachmentBytes(Message m) async {
    if (m.attachmentUrl == null || m.attachmentUrl!.isEmpty) {
      return null;
    }
    try {
      final name = m.attachmentFilename ?? 'файл';
      final cached = await getCachedAttachmentBytes(widget.peer.id, m.id, name);
      if (cached != null) {
        return Uint8List.fromList(cached);
      }

      final raw = await Api.getAttachmentBytes(m.attachmentUrl!);
      Uint8List bytes = Uint8List.fromList(raw);
      if (m.attachmentEncrypted) {
        final key = m.isMine
            ? widget.peer.publicKey
            : (m.senderPublicKey ?? widget.peer.publicKey);
        if (key == null) {
          return null;
        }
        final dec = await _e2ee.decryptBytes(bytes, key);
        if (dec == null) {
          return null;
        }
        bytes = dec;
      }
      await putCachedAttachment(widget.peer.id, m.id, name, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _text.removeListener(_onTextChanged);
    if (_isRecording) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _wsUnsub?.call();
    _text.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    final peerId = widget.peer.id;
    // Сразу помечаем прочитанными и обновляем локальный кэш — счётчик должен исчезнуть.
    // Важно: await, чтобы при возврате в список сервер уже вернул unread_count = 0.
    try {
      await Api(auth.token).markMessagesRead(peerId);
      await LocalDb.clearChatUnread(peerId);
      if (mounted) {
        try {
          context.read<ChatListRefreshService>().requestRefresh();
        } catch (_) {}
      }
    } catch (_) {}
    setState(() {
      _loading = true;
      _error = null;
    });
    final cached = await LocalDb.getMessages(peerId);
    final myId = auth.user?.id;
    var decryptedCachedById = <int, Message>{};
    if (cached.isNotEmpty && mounted) {
      final decryptedCached = <Message>[];
      for (final m in cached) {
        final dec = await _decryptMessage(m, myId: myId);
        decryptedCached.add(dec);
        decryptedCachedById[dec.id] = dec;
        if (!dec.content.startsWith('e2ee:')) {
          await LocalDb.upsertMessage(dec, peerId);
        }
      }
      setState(() => _messages = decryptedCached);
    }
    try {
      final api = Api(auth.token);
      final list = await api.getMessages(peerId);
      if (!mounted) {
        return;
      }
      final ws = _ws ?? context.read<WsService>();
      await _drainIncoming(ws);
      final cachedById = decryptedCachedById;
      final decryptedList = <Message>[];
      for (final m in list) {
        final dec = await _decryptMessage(m, myId: myId);
        Message toAdd = dec;
        if (dec.content.startsWith('e2ee:')) {
          final fromCache = cachedById[dec.id];
          if (fromCache != null && !fromCache.content.startsWith('e2ee:')) {
            toAdd = fromCache;
          }
        }
        decryptedList.add(toAdd);
        if (!toAdd.content.startsWith('e2ee:')) {
          await LocalDb.upsertMessage(toAdd, peerId);
        }
      }
      if (!mounted) {
        return;
      }
      final fromDb = await LocalDb.getMessages(peerId);
      final merged = <Message>[...decryptedList];
      final mergedIds = merged.map((m) => m.id).toSet();
      for (final m in fromDb) {
        if (!mergedIds.contains(m.id)) {
          final dec = await _decryptMessage(m, myId: myId);
          merged.add(dec);
          mergedIds.add(dec.id);
          if (!dec.content.startsWith('e2ee:')) {
            await LocalDb.upsertMessage(dec, peerId);
          }
        }
      }
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = merged;
        _loading = false;
      });
      _scrollToBottom(force: true); // При загрузке всегда прокручиваем вниз
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } catch (e) {
      logUserActionError('load_chat_messages', e, StackTrace.current);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e is ApiException ? e.message : 'Ошибка загрузки';
        _loading = false;
        if (_messages.isEmpty) {
          _messages = cached;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  /// Проверяет, находится ли пользователь внизу списка сообщений
  bool _isAtBottom() {
    if (!_scroll.hasClients) {
      return false;
    }
    final position = _scroll.position;
    // Считаем что пользователь внизу, если он находится в пределах 100px от конца
    return position.pixels >= position.maxScrollExtent - 100;
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        // Прокручиваем только если пользователь внизу или принудительно
        if (force || _isAtBottom()) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _setReaction(Message m, String emoji) async {
    try {
      final reactions = await Api(
        context.read<AuthService>().token,
      ).setMessageReaction(m.id, emoji);
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
    final auth = context.read<AuthService>().user;
    final myId = auth?.id;
    final theme = Theme.of(context);
    return r.userIds.take(3).map((userId) {
      String? avatarUrl;
      if (userId == widget.peer.id) {
        avatarUrl = widget.peer.avatarUrl;
      } else if (userId == myId) {
        avatarUrl = auth?.avatarUrl;
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
                  userId == myId
                      ? (auth?.displayName.isNotEmpty == true
                            ? auth!.displayName[0].toUpperCase()
                            : '?')
                      : (widget.peer.displayName.isNotEmpty
                            ? widget.peer.displayName[0].toUpperCase()
                            : '?'),
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

  void _showMessageActions(Message m, [Offset? position]) {
    void openSheet() {
      showModalBottomSheet<void>(
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
                        _setReaction(m, emoji);
                      },
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Ответить'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _replyingTo = m);
                },
              ),
              if (m.isMine &&
                  m.messageType == 'text' &&
                  m.attachmentUrl == null &&
                  !m.isPoll)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditDialog(m);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Переслать'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showForwardPicker(m);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(context.tr('delete_for_me')),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(m, forMe: true);
                },
              ),
              if (m.isMine)
                ListTile(
                  leading: Icon(Icons.delete_forever, color: Theme.of(ctx).colorScheme.error),
                  title: Text(context.tr('delete_for_all')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(m, forMe: false);
                  },
                ),
            ],
          ),
        ),
      );
    }

    if (position != null) {
      final screen = MediaQuery.sizeOf(context);
      final menuPosition = RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        screen.width - position.dx,
        screen.height - position.dy,
      );
      showMenu<void>(
        context: context,
        position: menuPosition,
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
              setState(() => _replyingTo = m);
            },
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.reply),
              title: Text('Ответить'),
            ),
          ),
          if (m.isMine &&
              m.messageType == 'text' &&
              m.attachmentUrl == null &&
              !m.isPoll)
            PopupMenuItem(
              onTap: () {
                if (!mounted) return;
                _showEditDialog(m);
              },
              child: const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(Icons.edit_outlined),
                title: Text('Редактировать'),
              ),
            ),
          PopupMenuItem(
            onTap: () {
              if (!mounted) return;
              _showForwardPicker(m);
            },
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.forward),
              title: Text('Переслать'),
            ),
          ),
          PopupMenuItem(
            onTap: () {
              if (!mounted) return;
              _deleteMessage(m, forMe: true);
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(context.tr('delete_for_me')),
            ),
          ),
          if (m.isMine)
            PopupMenuItem(
              onTap: () {
                if (!mounted) return;
                _deleteMessage(m, forMe: false);
              },
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text(context.tr('delete_for_all')),
              ),
            ),
        ],
      );
    } else {
      openSheet();
    }
  }

  Future<void> _deleteMessage(Message m, {required bool forMe}) async {
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).deleteMessage(m.id, forMe: forMe);
      if (!mounted) return;
      if (forMe) {
        setState(() => _messages.removeWhere((msg) => msg.id == m.id));
        await LocalDb.deleteMessage(peerId: widget.peer.id, messageId: m.id);
      } else {
        setState(() => _messages.removeWhere((msg) => msg.id == m.id));
        await LocalDb.deleteMessage(peerId: widget.peer.id, messageId: m.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : context.tr('connection_error')),
        ),
      );
    }
  }

  Future<void> _showEditDialog(Message m) async {
    final controller = TextEditingController(text: m.content);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать сообщение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Текст сообщения',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) {
      return;
    }
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).editMessage(m.id, result);
      if (!mounted) return;
      final idx = _messages.indexWhere((msg) => msg.id == m.id);
      if (idx >= 0) {
        final updated = _messages[idx].copyWith(content: result);
        setState(() => _messages[idx] = updated);
        await LocalDb.upsertMessage(updated, widget.peer.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : context.tr('connection_error')),
        ),
      );
    }
  }

  Future<void> _showForwardPicker(Message m) async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    List<ChatPreview> chats;
    try {
      chats = await Api(auth.token).getChats();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ошибка загрузки чатов')));
      return;
    }
    if (!mounted) {
      return;
    }
    final peerId = widget.peer.id;
    final others = chats
        .where((c) => c.peer?.id != null && c.peer!.id != peerId)
        .toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет других чатов для пересылки')),
      );
      return;
    }
    final selected = await showModalBottomSheet<ChatPreview>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Переслать в чат',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ...others.map((chat) {
              final p = chat.peer;
              if (p == null) {
                return const SizedBox.shrink();
              }
              return ListTile(
                title: Text(p.displayName),
                subtitle: Text('@${p.username}'),
                onTap: () => Navigator.pop(ctx, chat),
              );
            }),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    final selectedPeer = selected.peer;
    if (selectedPeer == null) {
      return;
    }
    final content = m.content;
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Переслать можно только текстовые сообщения'),
        ),
      );
      return;
    }
    final fromName = m.isMine
        ? (auth.user?.displayName ?? auth.user?.username ?? 'Я')
        : widget.peer.displayName;
    setState(() => _sending = true);
    try {
      final api = Api(auth.token);
      await api.sendMessage(
        selectedPeer.id,
        content,
        isForwarded: true,
        forwardFromSenderId: m.senderId,
        forwardFromDisplayName: fromName,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Переслано в чат с ${selectedPeer.displayName}'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Ошибка пересылки'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  bool get _canSend {
    if (_sending) {
      return false;
    }
    if (_text.text.trim().isNotEmpty) {
      return true;
    }
    if (_pendingAttachment != null) {
      return true;
    }
    if (_pendingMultipleFiles != null && _pendingMultipleFiles!.isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<void> _send() async {
    if (!_canSend) {
      return;
    }
    final content = _text.text.trim();
    logUserAction('send_message', {'peerId': widget.peer.id, 'hasFile': _pendingAttachment != null, 'hasMulti': _pendingMultipleFiles != null});
    final replyToId = _replyingTo?.id;
    final pending = _pendingAttachment;
    final pendingMulti = _pendingMultipleFiles;
    setState(() {
      _sending = true;
      _replyingTo = null;
      _text.clear();
      _pendingAttachment = null;
      _pendingMultipleFiles = null;
    });
    final api = Api(context.read<AuthService>().token);

    if (pendingMulti != null && pendingMulti.isNotEmpty) {
      try {
        final list = pendingMulti
            .map((f) => (bytes: f.bytes.toList(), filename: f.filename))
            .toList();
        final encrypted = pendingMulti.first.encrypted;
        final messages = await api.sendMessageWithMultipleFiles(
          widget.peer.id,
          content,
          list,
          attachmentEncrypted: encrypted,
        );
        if (!mounted) {
          return;
        }
        for (final msg in messages) {
          await LocalDb.upsertMessage(msg, widget.peer.id);
        }
        if (messages.isNotEmpty) {
          await LocalDb.updateChatLastMessage(widget.peer.id, messages.last);
        }
        setState(() {
          _messages.addAll(messages);
          _sending = false;
        });
        _scrollToBottom();
        _focusNode.requestFocus();
      } catch (e) {
        logUserActionError('send_message_multifile', e);
        if (!mounted) {
          return;
        }
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Ошибка отправки'),
          ),
        );
      }
      return;
    }

    if (pending != null) {
      try {
        if (pending is PendingFile) {
          final msg = await api.sendMessageWithFile(
            widget.peer.id,
            content,
            pending.bytes.toList(),
            pending.filename,
            attachmentEncrypted: pending.encrypted,
          );
          if (!mounted) {
            return;
          }
          await LocalDb.upsertMessage(msg, widget.peer.id);
          await LocalDb.updateChatLastMessage(widget.peer.id, msg);
          setState(() {
            _messages.add(msg);
            _sending = false;
          });
          _scrollToBottom();
          _focusNode.requestFocus();
        } else if (pending is PendingVoice) {
          final msg = await api.sendVoiceMessage(
            widget.peer.id,
            pending.bytes.toList(),
            'voice.m4a',
            pending.durationSec,
            attachmentEncrypted: pending.encrypted,
          );
          if (!mounted) {
            return;
          }
          await LocalDb.upsertMessage(msg, widget.peer.id);
          await LocalDb.updateChatLastMessage(widget.peer.id, msg);
          setState(() {
            _messages.add(msg);
            _sending = false;
          });
          _scrollToBottom();
          _focusNode.requestFocus();
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Ошибка отправки'),
          ),
        );
      }
      return;
    }

    String toSend = content;
    try {
      if (widget.peer.publicKey != null) {
        final encrypted = await _e2ee.encrypt(content, widget.peer.publicKey);
        if (encrypted != null) {
          toSend = encrypted;
        }
      }
      final msg = await api.sendMessage(
        widget.peer.id,
        toSend,
        replyToId: replyToId,
      );
      if (!mounted) {
        return;
      }
      final toShow = toSend != content
          ? Message(
              id: msg.id,
              senderId: msg.senderId,
              receiverId: msg.receiverId,
              content: content,
              createdAt: msg.createdAt,
              readAt: msg.readAt,
              isMine: msg.isMine,
              attachmentUrl: msg.attachmentUrl,
              attachmentFilename: msg.attachmentFilename,
              messageType: msg.messageType,
              pollId: msg.pollId,
              poll: msg.poll,
              attachmentKind: msg.attachmentKind,
              attachmentDurationSec: msg.attachmentDurationSec,
              senderPublicKey: msg.senderPublicKey,
              attachmentEncrypted: msg.attachmentEncrypted,
              replyToId: msg.replyToId,
              replyToContent: msg.replyToContent,
              replyToSenderName: msg.replyToSenderName,
              isForwarded: msg.isForwarded,
              forwardFromSenderId: msg.forwardFromSenderId,
              forwardFromDisplayName: msg.forwardFromDisplayName,
              reactions: msg.reactions,
            )
          : msg;
      await LocalDb.upsertMessage(toShow, widget.peer.id);
      await LocalDb.updateChatLastMessage(widget.peer.id, toShow);
      setState(() {
        _messages.add(toShow);
        _sending = false;
      });
      _scrollToBottom();
      _focusNode.requestFocus();
    } catch (e) {
      logUserActionError('send_message', e);
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      // Проверяем тип ошибки
      if (e is ApiException) {
        // Если статус 201 - сообщение успешно отправлено на сервер
        if (e.statusCode == 201) {
          // Сообщение отправлено, но была ошибка парсинга ответа
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Сообщение отправлено, но произошла ошибка при обработке ответа: ${e.message}',
              ),
            ),
          );
          return;
        }
        // Для всех остальных ApiException (400, 401, 500 и т.д.) - запрос дошел до сервера
        // Это не "нет связи", а ошибка сервера/валидации - не добавляем в outbox
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }

      // Проверяем, является ли это реальной сетевой ошибкой
      // (когда запрос вообще не дошел до сервера - нет интернета, таймаут и т.д.)
      if (ErrorUtils.isNetworkError(e)) {
        // Только для реальных сетевых ошибок (нет интернета) добавляем в outbox
        await LocalDb.addToOutbox(widget.peer.id, toSend);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нет связи. Сообщение будет отправлено при появлении сети.',
              ),
            ),
          );
        }
      } else {
        // Для других ошибок просто показываем сообщение
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: ${e.toString()}')),
        );
      }
    }
  }

  static const int _maxMultipleFiles = 10;

  Future<void> _attachFile() async {
    if (_sending) return;
    logUserAction('chat_attach_file');
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
    if (files.length == 1) {
      final file = files.single;
      var bytes = Uint8List.fromList(file.bytes!);
      var encrypted = false;
      if (widget.peer.publicKey != null) {
        final enc = await _e2ee.encryptBytes(bytes, widget.peer.publicKey);
        if (enc != null) {
          bytes = enc;
          encrypted = true;
        }
      }
      final name = file.name.toLowerCase();
      final isImage =
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp');
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingAttachment = PendingFile(
          bytes: bytes,
          filename: file.name,
          isImage: isImage,
          encrypted: encrypted,
        );
        _pendingMultipleFiles = null;
      });
      return;
    }
    final list = <PendingFile>[];
    for (final file in files) {
      var bytes = Uint8List.fromList(file.bytes!);
      var encrypted = false;
      if (widget.peer.publicKey != null) {
        final enc = await _e2ee.encryptBytes(bytes, widget.peer.publicKey);
        if (enc != null) {
          bytes = enc;
          encrypted = true;
        }
      }
      final name = file.name.toLowerCase();
      final isImage =
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp');
      list.add(
        PendingFile(
          bytes: bytes,
          filename: file.name,
          isImage: isImage,
          encrypted: encrypted,
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingAttachment = null;
      _pendingMultipleFiles = list;
    });
  }

  Future<void> _sendLocation() async {
    if (_sending) return;
    logUserAction('send_location', {'peerId': widget.peer.id});
    final token = context.read<AuthService>().token;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Геолокация отключена')),
      );
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступа к геолокации')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final api = Api(token);
      final msg = await api.sendMessageWithLocation(
        widget.peer.id,
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      await LocalDb.upsertMessage(msg, widget.peer.id);
      await LocalDb.updateChatLastMessage(widget.peer.id, msg);
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      logUserActionError('send_location', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка: $e')),
      );
      setState(() => _sending = false);
    }
  }

  Future<void> _createPoll() async {
    if (_sending) return;
    logUserAction('chat_create_poll');
    final result = await showDialog<_PollFormResult>(
      context: context,
      builder: (_) => const _CreatePollDialog(),
    );
    if (result == null ||
        result.question.trim().isEmpty ||
        result.options.length < 2) {
      return;
    }
    setState(() => _sending = true);
    if (!mounted) {
      return;
    }
    try {
      final api = Api(context.read<AuthService>().token);
      final msg = await api.sendPoll(
        widget.peer.id,
        result.question.trim(),
        result.options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        multiple: result.multiple,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Ошибка создания опроса',
          ),
        ),
      );
    }
  }

  void _updatePollAfterVote(int pollId, PollResult result) {
    final idx = _messages.indexWhere((m) => m.pollId == pollId);
    if (idx < 0) {
      return;
    }
    final m = _messages[idx];
    if (m.poll == null) {
      return;
    }
    final newOptions = result.options
        .map((o) => PollOption(text: o.text, votes: o.votes, voted: o.voted))
        .toList();
    final newPoll = PollData(
      id: m.poll!.id,
      question: m.poll!.question,
      options: newOptions,
      multiple: m.poll!.multiple,
    );
    final newMsg = Message(
      id: m.id,
      senderId: m.senderId,
      receiverId: m.receiverId,
      content: m.content,
      createdAt: m.createdAt,
      readAt: m.readAt,
      isMine: m.isMine,
      attachmentUrl: m.attachmentUrl,
      attachmentFilename: m.attachmentFilename,
      messageType: m.messageType,
      pollId: m.pollId,
      poll: newPoll,
      attachmentKind: m.attachmentKind,
      attachmentDurationSec: m.attachmentDurationSec,
      senderPublicKey: m.senderPublicKey,
      attachmentEncrypted: m.attachmentEncrypted,
      replyToId: m.replyToId,
      replyToContent: m.replyToContent,
      replyToSenderName: m.replyToSenderName,
      isForwarded: m.isForwarded,
      forwardFromSenderId: m.forwardFromSenderId,
      forwardFromDisplayName: m.forwardFromDisplayName,
      reactions: m.reactions,
    );
    setState(() => _messages[idx] = newMsg);
  }

  DateTime? _recordStartTime;

  Future<void> _startVoiceRecord() async {
    if (_sending || _isRecording) {
      return;
    }
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
        return;
      }
      final path = kIsWeb
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'
          : p.join(
              (await getTemporaryDirectory()).path,
              'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            );
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
        path: path,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = true;
        _recordPath = path;
        _recordStartTime = DateTime.now();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Permission')
                ? 'Нет доступа к микрофону'
                : 'Ошибка записи',
          ),
        ),
      );
    }
  }

  Future<void> _stopVoiceRecord() async {
    if (!_isRecording || _recordPath == null) {
      return;
    }
    final startTime = _recordStartTime;
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _recordPath = null;
        _recordStartTime = null;
      });
      if (path == null || path.isEmpty) {
        return;
      }
      int durationSec = 0;
      if (!kIsWeb) {
        try {
          final ap = AudioPlayer();
          await ap.setFilePath(path);
          final d = ap.duration;
          durationSec = d?.inSeconds ?? 0;
          await ap.dispose();
        } catch (_) {}
      }
      if (durationSec < 1 && startTime != null) {
        durationSec = DateTime.now().difference(startTime).inSeconds;
      }
      if (durationSec < 1) {
        return;
      }
      var voiceBytes = Uint8List.fromList(await readVoiceFileBytes(path));
      var encrypted = false;
      if (widget.peer.publicKey != null) {
        final enc = await _e2ee.encryptBytes(voiceBytes, widget.peer.publicKey);
        if (enc != null) {
          voiceBytes = enc;
          encrypted = true;
        }
      }
      if (!mounted) {
        return;
      }
      setState(
        () => _pendingAttachment = PendingVoice(
          bytes: voiceBytes,
          durationSec: durationSec,
          encrypted: encrypted,
        ),
      );
    } catch (_) {}
  }

  Future<void> _openRecordVideoNote() async {
    if (_sending) return;
    logUserAction('chat_record_video_note');
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      AppPageRoute(
        builder: (_) => RecordVideoNoteScreen(
          peerId: widget.peer.id,
          peerPublicKey: widget.peer.publicKey,
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final msg = result['message'] as Message?;
    if (msg != null) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBarBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primary;
    final appBarFg = isDark ? theme.colorScheme.onSurface : Colors.white;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        title: Row(
          children: [
            UserAvatar(
              user: widget.peer,
              radius: 20,
              backgroundColor: isDark
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.2)
                  : Colors.white24,
              textStyle: TextStyle(
                color: appBarFg,
                fontSize: 20 * 0.6,
                fontWeight: FontWeight.w600,
              ),
              showOnlineIndicator: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.peer.displayName,
                    style: TextStyle(
                      color: appBarFg,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.peer.isOnline == true || (widget.peer.lastSeen != null && widget.peer.lastSeen!.isNotEmpty)
                        ? formatLastSeen(context, widget.peer.lastSeen, widget.peer.isOnline)
                        : '@${widget.peer.username}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.peer.isOnline == true
                          ? Colors.greenAccent
                          : appBarFg.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: appBarFg),
        actionsIconTheme: IconThemeData(color: appBarFg),
        actions: [
          if (MediaQuery.sizeOf(context).width >= AppSizes.mobileBreakpoint) ...[
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Профиль',
              onPressed: () {
                logUserAction('chat_open_profile', {'peerId': widget.peer.id});
                Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => UserProfileScreen(user: widget.peer),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.phone),
              tooltip: 'Голосовой звонок',
              onPressed: () {
                logUserAction('chat_start_audio_call', {'peerId': widget.peer.id});
                Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => CallScreen(
                      peer: widget.peer,
                      isIncoming: false,
                      isVideoCall: false,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam),
              tooltip: 'Видеозвонок',
              onPressed: () {
                logUserAction('chat_start_video_call', {'peerId': widget.peer.id});
                Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => CallScreen(
                      peer: widget.peer,
                      isIncoming: false,
                      isVideoCall: true,
                    ),
                  ),
                );
              },
            ),
          ] else
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: appBarFg),
              onSelected: (value) {
                if (value == 'profile') {
                  Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) => UserProfileScreen(user: widget.peer),
                    ),
                  );
                } else if (value == 'voice') {
                  Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) => CallScreen(
                        peer: widget.peer,
                        isIncoming: false,
                        isVideoCall: false,
                      ),
                    ),
                  );
                } else if (value == 'video') {
                  Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) => CallScreen(
                        peer: widget.peer,
                        isIncoming: false,
                        isVideoCall: true,
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Профиль'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'voice',
                  child: Row(
                    children: [
                      Icon(Icons.phone, size: 20),
                      SizedBox(width: 12),
                      Text('Голосовой звонок'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'video',
                  child: Row(
                    children: [
                      Icon(Icons.videocam, size: 20),
                      SizedBox(width: 12),
                      Text('Видеозвонок'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: 10,
                    itemBuilder: (context, i) =>
                        SkeletonMessageBubble(isRight: i.isOdd),
                  )
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
                        TextButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      // Специальное отображение для пропущенных звонков
                      if (m.messageType == 'missed_call') {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.phone_missed,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  m.isMine
                                      ? 'Пропущенный звонок'
                                      : 'Пропущенный звонок',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return Align(
                        alignment: m.isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => _showMessageActions(m),
                          onSecondaryTapDown: (details) =>
                              _showMessageActions(m, details.globalPosition),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: m.isMine
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.25
                                        : 0.06,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (m.isForwarded) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forward,
                                        size: 14,
                                        color:
                                            (m.isMine
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface)
                                                .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'От ${m.forwardFromDisplayName ?? '?'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  (m.isMine
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .onPrimary
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurface)
                                                      .withValues(alpha: 0.8),
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (m.replyToId != null &&
                                    (m.replyToContent != null ||
                                        m.replyToSenderName != null)) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          (m.isMine
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.onPrimary
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface)
                                              .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (m.replyToSenderName != null)
                                          Text(
                                            m.replyToSenderName!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: m.isMine
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                ),
                                          ),
                                        if (m.replyToContent != null &&
                                            m.replyToContent!.isNotEmpty)
                                          Text(
                                            _safeMessageContent(
                                              m.replyToContent,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      (m.isMine
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onPrimary
                                                              : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface)
                                                          .withValues(
                                                            alpha: 0.9,
                                                          ),
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (m.isPoll && m.poll != null)
                                  _buildPollBubble(m)
                                else if (m.isVoice)
                                  VoiceMessageBubble(
                                    audioUrl: m.attachmentEncrypted
                                        ? null
                                        : m.attachmentUrl,
                                    audioBytesFuture: m.attachmentEncrypted
                                        ? _getAttachmentBytes(
                                            m,
                                          ).then((b) => b?.toList() ?? <int>[])
                                        : null,
                                    durationSec: m.attachmentDurationSec ?? 0,
                                    isMine: m.isMine,
                                  )
                                else if (m.isVideoNote)
                                  _buildVideoNoteBubble(m)
                                else if (m.isLocation)
                                  _buildLocationBubble(m)
                                else ...[
                                  if (m.content.isNotEmpty &&
                                      !_isFilePlaceholderContent(m))
                                    SelectableText(
                                      _safeMessageContent(m.content),
                                      style: TextStyle(
                                        color: m.isMine
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                    ),
                                  if (m.hasAttachment) ...[
                                    if (m.content.isNotEmpty &&
                                        !_isFilePlaceholderContent(m))
                                      const SizedBox(height: 8),
                                    _buildAttachment(m),
                                  ],
                                ],
                                if (m.reactions.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: m.reactions.map((r) {
                                      final myId = context
                                          .read<AuthService>()
                                          .user
                                          ?.id;
                                      final hasMine =
                                          myId != null &&
                                          r.userIds.contains(myId);
                                      return InkWell(
                                        onTap: () {
                                          if (hasMine) {
                                            _setReaction(m, r.emoji);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (m.isMine
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .onPrimary
                                                        : Theme.of(
                                                            context,
                                                          ).colorScheme.surface)
                                                    .withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ..._reactionAvatars(context, r),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${r.emoji} ${r.count > 1 ? r.count : ''}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: m.isMine
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .onPrimary
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurface,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatTime(m.createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: m.isMine
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary
                                                      .withValues(alpha: 0.8)
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                    ),
                                    if (m.isMine) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        m.readAt != null
                                            ? Icons.done_all
                                            : Icons.done,
                                        size: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                            .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        m.readAt != null
                                            ? 'Прочитано'
                                            : 'Отправлено',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                                  .withValues(alpha: 0.8),
                                              fontSize: 11,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_replyingTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ответ на ${_replyingTo!.isMine ? 'ваше сообщение' : widget.peer.displayName}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        if (_replyingTo!.content.isNotEmpty)
                          Text(
                            () {
                              final safe = _safeMessageContent(
                                _replyingTo!.content,
                              );
                              return safe.length > 60
                                  ? '${safe.substring(0, 57)}...'
                                  : safe;
                            }(),
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
                    tooltip: 'Отмена',
                  ),
                ],
              ),
            ),
          if (_ws != null)
            Builder(
              builder: (context) {
                final typing = _ws!.getPeerTyping(widget.peer.id);
                if (typing == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('typing').replaceFirst('%s', typing),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              },
            ),
          if (_pendingMultipleFiles != null &&
              _pendingMultipleFiles!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  if (_pendingMultipleFiles!.length == 1)
                    Icon(
                      Icons.insert_drive_file,
                      color: Theme.of(context).colorScheme.primary,
                      size: 40,
                    )
                  else
                    Icon(
                      Icons.photo_library,
                      color: Theme.of(context).colorScheme.primary,
                      size: 40,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pendingMultipleFiles!.length == 1
                          ? _pendingMultipleFiles!.first.filename
                          : '${_pendingMultipleFiles!.length} файлов',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        setState(() => _pendingMultipleFiles = null),
                    tooltip: 'Убрать вложения',
                  ),
                ],
              ),
            ),
          if (_pendingAttachment != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  if (_pendingAttachment is PendingFile) ...[
                    if ((_pendingAttachment! as PendingFile).isImage &&
                        !(_pendingAttachment! as PendingFile).encrypted)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          (_pendingAttachment! as PendingFile).bytes,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Icon(
                        Icons.insert_drive_file,
                        color: Theme.of(context).colorScheme.primary,
                        size: 40,
                      ),
                  ] else if (_pendingAttachment is PendingVoice) ...[
                    Icon(
                      Icons.mic,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(
                        (_pendingAttachment! as PendingVoice).durationSec,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pendingAttachment is PendingFile
                          ? (_pendingAttachment! as PendingFile).filename
                          : 'Голосовое сообщение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _pendingAttachment = null),
                    tooltip: 'Убрать вложение',
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.3
                        : 0.06,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  enabled: !_sending,
                  tooltip: 'Вложения',
                  icon: const Icon(Icons.attach_file),
                  onSelected: (value) {
                    switch (value) {
                      case 'file':
                        _attachFile();
                        break;
                      case 'poll':
                        _createPoll();
                        break;
                      case 'video':
                        _openRecordVideoNote();
                        break;
                      case 'location':
                        _sendLocation();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'file',
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined),
                          SizedBox(width: 12),
                          Text('Фото или файл'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'poll',
                      child: Row(
                        children: [
                          Icon(Icons.poll_outlined),
                          SizedBox(width: 12),
                          Text('Опрос'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'video',
                      child: Row(
                        children: [
                          Icon(Icons.videocam_rounded),
                          SizedBox(width: 12),
                          Text('Видеокружок'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'location',
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined),
                          SizedBox(width: 12),
                          Text('Геолокация'),
                        ],
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onLongPressStart: (_) => _startVoiceRecord(),
                  onLongPressEnd: (_) => _stopVoiceRecord(),
                  child: IconButton(
                    onPressed: _sending
                        ? null
                        : () {
                            if (_isRecording) {
                              _stopVoiceRecord();
                            } else {
                              _startVoiceRecord();
                            }
                          },
                    icon: _isRecording
                        ? const Icon(Icons.stop_circle, color: Colors.red)
                        : const Icon(Icons.mic_none),
                    tooltip: _isRecording
                        ? 'Остановить запись'
                        : 'Нажмите для записи голосового (или удерживайте)',
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focusNode,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.send,
                    enableInteractiveSelection: true,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_sending)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Отправка…',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  )
                else
                  IconButton(
                    onPressed: _sending ? null : () => _send(),
                    icon: Icon(
                      Icons.send,
                      color: _canSend
                          ? null
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.38),
                    ),
                    tooltip: 'Отправить',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoNoteBubble(Message m) {
    return VideoNoteBubble(
      videoUrl: m.attachmentEncrypted ? null : m.attachmentUrl,
      videoBytesFuture: m.attachmentEncrypted
          ? _getAttachmentBytes(m).then((b) => b?.toList() ?? <int>[])
          : null,
      durationSec: m.attachmentDurationSec,
      isMine: m.isMine,
    );
  }

  Widget _buildLocationBubble(Message m) {
    final loc = m.locationData;
    if (loc == null) {
      return Text(
        '📍 Геолокация',
        style: TextStyle(
          color: m.isMine
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    final url =
        'https://www.google.com/maps?q=${loc.lat},${loc.lng}';
    final textColor = m.isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: textColor, size: 24),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.label ?? '${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)}',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              Text(
                'Открыть на карте',
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPollBubble(Message m) {
    final poll = m.poll!;
    final isMine = m.isMine;
    final textColor = isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final totalVotes = poll.options.fold<int>(0, (s, o) => s + o.votes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.poll_outlined, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(
              'Опрос',
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          poll.question,
          style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
        ),
        const SizedBox(height: 8),
        ...poll.options.asMap().entries.map((entry) {
          final i = entry.key;
          final opt = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () async {
                try {
                  final api = Api(context.read<AuthService>().token);
                  final result = await api.votePoll(poll.id, i);
                  if (!mounted) {
                    return;
                  }
                  _updatePollAfterVote(poll.id, result);
                } catch (_) {}
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: textColor.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt.text,
                        style: TextStyle(color: textColor, fontSize: 14),
                      ),
                    ),
                    if (totalVotes > 0)
                      Text(
                        '${opt.votes}',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    if (opt.voted) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle, size: 16, color: textColor),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAttachment(Message m) {
    final url = m.attachmentUrl!;
    final name = m.attachmentFilename ?? 'файл';
    final isImage = _isImageFilename(name);
    final textColor = m.isMine
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    if (m.attachmentEncrypted) {
      final cacheKey =
          '${widget.peer.id}_${m.id}_${m.attachmentFilename ?? ""}';
      final future = _attachmentFutureCache.putIfAbsent(
        cacheKey,
        () => _getAttachmentBytes(m),
      );
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(name, style: TextStyle(color: textColor, fontSize: 12)),
              ],
            );
          }
          final bytes = snapshot.data!;
          if (isImage) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) =>
                          ImagePreviewScreen(imageBytes: bytes, filename: name),
                    ),
                  );
                },
                child: Image.memory(
                  bytes,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: textColor, size: 48),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: TextStyle(color: textColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return InkWell(
            onTap: () => _openDecryptedFile(bytes, name),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file, color: textColor, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(color: textColor, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Navigator.of(context).push(
              AppPageRoute(
                builder: (_) => ImagePreviewScreen(
                  imageUrl: url,
                  filename: name,
                  bytesFuture: Api.getAttachmentBytes(
                    url,
                  ).then((list) => Uint8List.fromList(list)),
                ),
              ),
            );
          },
          child: Image.network(
            url,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) {
                return child;
              }
              return SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                              (progress.expectedTotalBytes ?? 1)
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: textColor, size: 48),
                const SizedBox(width: 8),
                Text(name, style: TextStyle(color: textColor, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _openUrl(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: textColor, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: TextStyle(color: textColor, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDecryptedFile(Uint8List bytes, String filename) async {
    try {
      await saveOrDownloadFile(bytes, filename);
      if (mounted && kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл сохранён в загрузки')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть файл')),
        );
      }
    }
  }

  bool _isImageFilename(String name) {
    final lower = name.toLowerCase();
    final parts = lower.split('.');
    final ext = parts.length > 1 ? parts.last : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return true;
    }
    // Файлы без расширения или с типичными именами с камеры/галереи
    if (ext.isEmpty &&
        (lower.startsWith('img') ||
            lower.startsWith('photo') ||
            lower == 'image')) {
      return true;
    }
    return false;
  }

  /// Содержимое — служебная подпись «(файл)» при картинке: в пузыре не показываем.
  bool _isFilePlaceholderContent(Message m) {
    if (!m.hasAttachment) {
      return false;
    }
    final content = m.content.trim();
    if (content != '(файл)' && content.isNotEmpty) return false;
    return _isImageFilename(m.attachmentFilename ?? '');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatTime(String iso) {
    try {
      final d = DateTime.parse(iso);
      final n = DateTime.now();
      if (d.year == n.year && d.month == n.month && d.day == n.day) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      return '${d.day}.${d.month}.${d.year}';
    } catch (_) {
      return iso;
    }
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Текст для отображения: не показываем шифротекст и «кракозябры» после неудачной расшифровки.
  static const String _undecryptedPlaceholder =
      'Сообщение не удалось расшифровать';

  String _safeMessageContent(String? content) {
    if (content == null || content.isEmpty) {
      return '';
    }
    if (content.startsWith('e2ee:')) {
      return _undecryptedPlaceholder;
    }
    if (content.length > 24 &&
        RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(content)) {
      return _undecryptedPlaceholder;
    }
    final replacementCount = content.runes.where((r) => r == 0xFFFD).length;
    if (content.isNotEmpty && replacementCount > content.length ~/ 2) {
      return _undecryptedPlaceholder;
    }
    return content;
  }
}

class _PollFormResult {
  final String question;
  final List<String> options;
  final bool multiple;
  _PollFormResult({
    required this.question,
    required this.options,
    required this.multiple,
  });
}

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog();

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _questionController = TextEditingController();
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multiple = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 10) {
      return;
    }
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionControllers.length <= 2) {
      return;
    }
    setState(() {
      _optionControllers[i].dispose();
      _optionControllers.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый опрос'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: 'Вопрос',
                hintText: 'Текст вопроса',
              ),
              maxLines: 2,
              enableInteractiveSelection: true,
            ),
            const SizedBox(height: 16),
            ..._optionControllers.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: c,
                        decoration: InputDecoration(
                          labelText: 'Вариант ${i + 1}',
                          hintText: 'Текст варианта',
                        ),
                        enableInteractiveSelection: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _optionControllers.length <= 2
                          ? null
                          : () => _removeOption(i),
                    ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 10)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Добавить вариант'),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _multiple,
              onChanged: (v) => setState(() => _multiple = v ?? false),
              title: const Text('Несколько вариантов'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final question = _questionController.text.trim();
            final options = _optionControllers
                .map((c) => c.text.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (question.isEmpty || options.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Введите вопрос и минимум 2 варианта'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _PollFormResult(
                question: question,
                options: options,
                multiple: _multiple,
              ),
            );
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

abstract class PendingAttachment {}

class PendingFile extends PendingAttachment {
  final Uint8List bytes;
  final String filename;
  final bool isImage;
  final bool encrypted;
  PendingFile({
    required this.bytes,
    required this.filename,
    this.isImage = false,
    this.encrypted = false,
  });
}

class PendingVoice extends PendingAttachment {
  final Uint8List bytes;
  final int durationSec;
  final bool encrypted;
  PendingVoice({
    required this.bytes,
    required this.durationSec,
    this.encrypted = false,
  });
}
