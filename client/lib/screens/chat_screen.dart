import 'dart:typed_data';
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
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/attachment_cache.dart';
import '../services/e2ee_service.dart';
import '../services/ws_service.dart';
import '../utils/app_page_route.dart';
import '../utils/download_file.dart';
import '../utils/voice_file_io.dart';
import '../widgets/app_back_button.dart';
import '../widgets/skeleton.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/video_note_bubble.dart';
import 'call_screen.dart';
import 'record_video_note_screen.dart';
import 'user_profile_screen.dart';
import 'image_preview_screen.dart';

class ChatScreen extends StatefulWidget {
  final User peer;

  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
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

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    final ws = context.read<WsService>();
    _ws = ws;
    void onUpdate() {
      if (!mounted) return;
      _drainIncoming(ws);
    }
    _wsUnsub = () => ws.removeListener(onUpdate);
    ws.addListener(onUpdate);
    _drainIncoming(ws);
  }

  static const List<String> _reactionEmojis = ['👍', '👎', '❤️', '🔥', '😂', '😮', '😢'];

  Future<void> _drainIncoming(WsService ws) async {
    final myId = context.read<AuthService>().user?.id;
    Message? m;
    while ((m = ws.takeIncomingFor(widget.peer.id)) != null) {
      Message decrypted = await _decryptMessage(m!);
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
      if (!mounted) return;
      setState(() => _messages.add(decrypted));
    }
    ReactionUpdate? ru;
    while ((ru = ws.takeReactionUpdateFor(widget.peer.id)) != null) {
      final idx = _messages.indexWhere((msg) => msg.id == ru!.messageId);
      if (idx >= 0 && mounted) setState(() => _messages[idx] = _messages[idx].copyWith(reactions: ru!.reactions));
    }
    // Пользователь в чате — помечаем все сообщения прочитанными, чтобы при выходе не показывался счётчик непрочитанных
    if (mounted) {
      final auth = context.read<AuthService>();
      Api(auth.token).markMessagesRead(widget.peer.id).catchError((_) {});
    }
  }

  Future<Message> _decryptMessage(Message m) async {
    if (!m.content.startsWith('e2ee:') || m.senderPublicKey == null) return m;
    final decrypted = await _e2ee.decrypt(m.content, m.senderPublicKey);
    if (decrypted == null) return m;
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
    if (m.attachmentUrl == null || m.attachmentUrl!.isEmpty) return null;
    try {
      final name = m.attachmentFilename ?? 'файл';
      final cached = await getCachedAttachmentBytes(widget.peer.id, m.id, name);
      if (cached != null) return Uint8List.fromList(cached);

      final raw = await Api.getAttachmentBytes(m.attachmentUrl!);
      Uint8List bytes = Uint8List.fromList(raw);
      if (m.attachmentEncrypted) {
        final key = m.isMine ? widget.peer.publicKey : m.senderPublicKey;
        if (key == null) return null;
        final dec = await _e2ee.decryptBytes(bytes, key);
        if (dec == null) return null;
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
    if (_isRecording) _audioRecorder.stop();
    _audioRecorder.dispose();
    _wsUnsub?.call();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final peerId = widget.peer.id;
    final cached = await LocalDb.getMessages(peerId);
    if (cached.isNotEmpty && mounted) setState(() => _messages = cached);
    try {
      final api = Api(auth.token);
      final list = await api.getMessages(peerId);
      if (!mounted) return;
      final ws = _ws ?? context.read<WsService>();
      await _drainIncoming(ws);
      final decryptedList = <Message>[];
      for (final m in list) {
        final dec = await _decryptMessage(m);
        decryptedList.add(dec);
        await LocalDb.upsertMessage(dec, peerId);
      }
      if (!mounted) return;
      final fromDb = await LocalDb.getMessages(peerId);
      setState(() {
        _messages = fromDb.isNotEmpty ? fromDb : decryptedList;
        _loading = false;
      });
      _scrollToBottom();
      await api.markMessagesRead(peerId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Ошибка загрузки';
        _loading = false;
        if (_messages.isEmpty) _messages = cached;
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

  Future<void> _setReaction(Message m, String emoji) async {
    try {
      final reactions = await Api(context.read<AuthService>().token).setMessageReaction(m.id, emoji);
      if (!mounted) return;
      final idx = _messages.indexWhere((msg) => msg.id == m.id);
      if (idx >= 0) setState(() => _messages[idx] = _messages[idx].copyWith(reactions: reactions));
    } catch (_) {}
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
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Переслать'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showForwardPicker(m);
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
              if (!mounted) return;
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
              if (!mounted) return;
              setState(() => _replyingTo = m);
            },
            child: const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.reply),
              title: Text('Ответить'),
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
        ],
      );
    } else {
      openSheet();
    }
  }

  Future<void> _showForwardPicker(Message m) async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    List<ChatPreview> chats;
    try {
      chats = await Api(auth.token).getChats();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка загрузки чатов')));
      return;
    }
    if (!mounted) return;
    final peerId = widget.peer.id;
    final others = chats.where((c) => c.peer?.id != null && c.peer!.id != peerId).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет других чатов для пересылки')));
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
              child: Text('Переслать в чат', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ...others.map((chat) {
              final p = chat.peer;
              if (p == null) return const SizedBox.shrink();
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
    if (selected == null || !mounted) return;
    final selectedPeer = selected.peer;
    if (selectedPeer == null) return;
    final content = m.content;
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Переслать можно только текстовые сообщения')));
      return;
    }
    final fromName = m.isMine ? (auth.user?.displayName ?? auth.user?.username ?? 'Я') : widget.peer.displayName;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Переслано в чат с ${selectedPeer.displayName}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка пересылки')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool get _canSend {
    if (_sending) return false;
    if (_text.text.trim().isNotEmpty) return true;
    if (_pendingAttachment != null) return true;
    if (_pendingMultipleFiles != null && _pendingMultipleFiles!.isNotEmpty) return true;
    return false;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final content = _text.text.trim();
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
        if (!mounted) return;
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
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка отправки')),
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
          if (!mounted) return;
          await LocalDb.upsertMessage(msg, widget.peer.id);
          await LocalDb.updateChatLastMessage(widget.peer.id, msg);
          setState(() {
            _messages.add(msg);
            _sending = false;
          });
          _scrollToBottom();
        } else if (pending is PendingVoice) {
          final msg = await api.sendVoiceMessage(
            widget.peer.id,
            pending.bytes.toList(),
            'voice.m4a',
            pending.durationSec,
            attachmentEncrypted: pending.encrypted,
          );
          if (!mounted) return;
          await LocalDb.upsertMessage(msg, widget.peer.id);
          await LocalDb.updateChatLastMessage(widget.peer.id, msg);
          setState(() {
            _messages.add(msg);
            _sending = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка отправки')),
        );
      }
      return;
    }

    String toSend = content;
    try {
      if (widget.peer.publicKey != null) {
        final encrypted = await _e2ee.encrypt(content, widget.peer.publicKey);
        if (encrypted != null) toSend = encrypted;
      }
      final msg = await api.sendMessage(widget.peer.id, toSend, replyToId: replyToId);
      if (!mounted) return;
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      await LocalDb.addToOutbox(widget.peer.id, toSend);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет связи. Сообщение будет отправлено при появлении сети.'),
        ),
      );
    }
  }

  static const int _maxMultipleFiles = 10;

  Future<void> _attachFile() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final files = result.files
        .where((f) => f.bytes != null && f.bytes!.isNotEmpty)
        .take(_maxMultipleFiles)
        .toList();
    if (files.isEmpty) return;
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
      final isImage = name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif') || name.endsWith('.webp');
      if (!mounted) return;
      setState(() {
        _pendingAttachment = PendingFile(bytes: bytes, filename: file.name, isImage: isImage, encrypted: encrypted);
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
      final isImage = name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif') || name.endsWith('.webp');
      list.add(PendingFile(bytes: bytes, filename: file.name, isImage: isImage, encrypted: encrypted));
    }
    if (!mounted) return;
    setState(() {
      _pendingAttachment = null;
      _pendingMultipleFiles = list;
    });
  }

  Future<void> _createPoll() async {
    if (_sending) return;
    final result = await showDialog<_PollFormResult>(context: context, builder: (_) => const _CreatePollDialog());
    if (result == null || result.question.trim().isEmpty || result.options.length < 2) return;
    setState(() => _sending = true);
    try {
      final api = Api(context.read<AuthService>().token);
      final msg = await api.sendPoll(
        widget.peer.id,
        result.question.trim(),
        result.options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        multiple: result.multiple,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка создания опроса')),
      );
    }
  }

  void _updatePollAfterVote(int pollId, PollResult result) {
    final idx = _messages.indexWhere((m) => m.pollId == pollId);
    if (idx < 0) return;
    final m = _messages[idx];
    if (m.poll == null) return;
    final newOptions = result.options.map((o) => PollOption(text: o.text, votes: o.votes, voted: o.voted)).toList();
    final newPoll = PollData(id: m.poll!.id, question: m.poll!.question, options: newOptions, multiple: m.poll!.multiple);
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
    if (_sending || _isRecording) return;
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
        return;
      }
      final path = kIsWeb
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a'
          : p.join((await getTemporaryDirectory()).path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100), path: path);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordPath = path;
        _recordStartTime = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().contains('Permission') ? 'Нет доступа к микрофону' : 'Ошибка записи')),
      );
    }
  }

  Future<void> _stopVoiceRecord() async {
    if (!_isRecording || _recordPath == null) return;
    final startTime = _recordStartTime;
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordPath = null;
        _recordStartTime = null;
      });
      if (path == null || path.isEmpty) return;
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
      if (durationSec < 1) return;
      var voiceBytes = Uint8List.fromList(await readVoiceFileBytes(path));
      var encrypted = false;
      if (widget.peer.publicKey != null) {
        final enc = await _e2ee.encryptBytes(voiceBytes, widget.peer.publicKey);
        if (enc != null) {
          voiceBytes = enc;
          encrypted = true;
        }
      }
      if (!mounted) return;
      setState(() => _pendingAttachment = PendingVoice(bytes: voiceBytes, durationSec: durationSec, encrypted: encrypted));
    } catch (_) {}
  }

  Future<void> _openRecordVideoNote() async {
    if (_sending) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      AppPageRoute(
        builder: (_) => RecordVideoNoteScreen(peerId: widget.peer.id, peerPublicKey: widget.peer.publicKey),
      ),
    );
    if (result == null || !mounted) return;
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
    final appBarBg = isDark ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.primary;
    final appBarFg = isDark ? theme.colorScheme.onSurface : Colors.white;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.2) : Colors.white24,
              backgroundImage: widget.peer.avatarUrl != null && widget.peer.avatarUrl!.isNotEmpty
                  ? NetworkImage(widget.peer.avatarUrl!)
                  : null,
              child: widget.peer.avatarUrl == null || widget.peer.avatarUrl!.isEmpty
                  ? Icon(Icons.person, color: appBarFg.withValues(alpha: 0.8), size: 24)
                  : null,
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
                    '@${widget.peer.username}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appBarFg.withValues(alpha: 0.8),
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
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Профиль',
            onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => UserProfileScreen(user: widget.peer)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Видеозвонок',
            onPressed: () {
              Navigator.of(context).push(
                AppPageRoute(builder: (_) => CallScreen(peer: widget.peer, isIncoming: false)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: 10,
                    itemBuilder: (context, i) => SkeletonMessageBubble(isRight: i.isOdd),
                  )
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          return Align(
                            alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showMessageActions(m),
                              onSecondaryTapDown: (details) => _showMessageActions(m, details.globalPosition),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: m.isMine
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.06),
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
                                          Icon(Icons.forward, size: 14, color: (m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface).withOpacity(0.8)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'От ${m.forwardFromDisplayName ?? '?'}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: (m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface).withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    if (m.replyToId != null && (m.replyToContent != null || m.replyToSenderName != null)) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: (m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (m.replyToSenderName != null)
                                              Text(
                                                m.replyToSenderName!,
                                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  color: m.isMine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                            if (m.replyToContent != null && m.replyToContent!.isNotEmpty)
                                              Text(
                                                _safeMessageContent(m.replyToContent),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: (m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface).withOpacity(0.9),
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
                                        audioUrl: m.attachmentEncrypted ? null : m.attachmentUrl,
                                        audioBytesFuture: m.attachmentEncrypted
                                            ? _getAttachmentBytes(m).then((b) => b?.toList() ?? <int>[])
                                            : null,
                                        durationSec: m.attachmentDurationSec ?? 0,
                                        isMine: m.isMine,
                                      )
                                    else if (m.isVideoNote)
                                      _buildVideoNoteBubble(m)
                                    else ...[
                                    if (m.content.isNotEmpty && !_isFilePlaceholderContent(m))
                                      SelectableText(
                                        _safeMessageContent(m.content),
                                        style: TextStyle(
                                          color: m.isMine
                                              ? Theme.of(context).colorScheme.onPrimary
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    if (m.hasAttachment) ...[
                                      if (m.content.isNotEmpty && !_isFilePlaceholderContent(m)) const SizedBox(height: 8),
                                      _buildAttachment(m),
                                    ],
                                  ],
                                  if (m.reactions.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: m.reactions.map((r) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.surface).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('${r.emoji} ${r.count > 1 ? r.count : ''}', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: m.isMine ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                                          )),
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
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: m.isMine
                                              ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (m.isMine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          m.readAt != null ? Icons.done_all : Icons.done,
                                          size: 14,
                                          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          m.readAt != null ? 'Прочитано' : 'Отправлено',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
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
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
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
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (_replyingTo!.content.isNotEmpty)
                          Text(
                            () {
                              final safe = _safeMessageContent(_replyingTo!.content);
                              return safe.length > 60 ? '${safe.substring(0, 57)}...' : safe;
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
          if (_pendingMultipleFiles != null && _pendingMultipleFiles!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (_pendingMultipleFiles!.length == 1)
                    Icon(Icons.insert_drive_file, color: Theme.of(context).colorScheme.primary, size: 40)
                  else
                    Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary, size: 40),
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
                    onPressed: () => setState(() => _pendingMultipleFiles = null),
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
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (_pendingAttachment is PendingFile) ...[
                    if ((_pendingAttachment! as PendingFile).isImage && !(_pendingAttachment! as PendingFile).encrypted)
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
                      Icon(Icons.insert_drive_file, color: Theme.of(context).colorScheme.primary, size: 40),
                  ] else if (_pendingAttachment is PendingVoice) ...[
                    Icon(Icons.mic, color: Theme.of(context).colorScheme.primary, size: 32),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration((_pendingAttachment! as PendingVoice).durationSec),
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
                  color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _sending ? null : _attachFile,
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Фото или файл',
                ),
                IconButton(
                  onPressed: _sending ? null : _createPoll,
                  icon: const Icon(Icons.poll_outlined),
                  tooltip: 'Опрос',
                ),
                GestureDetector(
                  onLongPressStart: (_) => _startVoiceRecord(),
                  onLongPressEnd: (_) => _stopVoiceRecord(),
                  child: IconButton(
                    onPressed: _sending ? null : () {
                      if (_isRecording) _stopVoiceRecord();
                      else _startVoiceRecord();
                    },
                    icon: _isRecording
                        ? const Icon(Icons.stop_circle, color: Colors.red)
                        : const Icon(Icons.mic_none),
                    tooltip: _isRecording ? 'Остановить запись' : 'Нажмите для записи голосового (или удерживайте)',
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _openRecordVideoNote,
                  icon: const Icon(Icons.videocam_rounded),
                  tooltip: 'Видеокружок',
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.send,
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  IconButton(
                    onPressed: _sending ? null : () => _send(),
                    icon: Icon(Icons.send, color: _canSend ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
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
            Text('Опрос', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8))),
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
                  if (!mounted) return;
                  _updatePollAfterVote(poll.id, result);
                } catch (_) {}
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: textColor.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(opt.text, style: TextStyle(color: textColor, fontSize: 14)),
                    ),
                    if (totalVotes > 0)
                      Text(
                        '${opt.votes}',
                        style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8)),
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
      return FutureBuilder<Uint8List?>(
        future: _getAttachmentBytes(m),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: textColor)),
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
                    AppPageRoute(builder: (_) => ImagePreviewScreen(imageBytes: bytes, filename: name)),
                  );
                },
                child: Image.memory(
                  bytes,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Row(
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
                  bytesFuture: Api.getAttachmentBytes(url).then((list) => Uint8List.fromList(list)),
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
              if (progress == null) return child;
              return SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1)
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Row(
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл сохранён в загрузки')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть файл')));
    }
  }

  bool _isImageFilename(String name) {
    final lower = name.toLowerCase();
    final parts = lower.split('.');
    final ext = parts.length > 1 ? parts.last : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return true;
    // Файлы без расширения или с типичными именами с камеры/галереи
    if (ext.isEmpty && (lower.startsWith('img') || lower.startsWith('photo') || lower == 'image')) return true;
    return false;
  }

  /// Содержимое — служебная подпись «(файл)» при картинке: в пузыре не показываем.
  bool _isFilePlaceholderContent(Message m) {
    if (!m.hasAttachment) return false;
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
  static const String _undecryptedPlaceholder = 'Сообщение не удалось расшифровать';

  String _safeMessageContent(String? content) {
    if (content == null || content.isEmpty) return '';
    if (content.startsWith('e2ee:')) return _undecryptedPlaceholder;
    if (content.length > 24 && RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(content)) return _undecryptedPlaceholder;
    final replacementCount = content.runes.where((r) => r == 0xFFFD).length;
    if (content.isNotEmpty && replacementCount > content.length ~/ 2) return _undecryptedPlaceholder;
    return content;
  }
}

class _PollFormResult {
  final String question;
  final List<String> options;
  final bool multiple;
  _PollFormResult({required this.question, required this.options, required this.multiple});
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
    if (_optionControllers.length >= 10) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionControllers.length <= 2) return;
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
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _optionControllers.length <= 2 ? null : () => _removeOption(i),
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
            final options = _optionControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
            if (question.isEmpty || options.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Введите вопрос и минимум 2 варианта')),
              );
              return;
            }
            Navigator.of(context).pop(_PollFormResult(question: question, options: options, multiple: _multiple));
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
