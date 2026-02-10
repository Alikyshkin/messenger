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
import '../utils/temp_file.dart';
import '../utils/voice_file_io.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/video_note_bubble.dart';
import 'call_screen.dart';
import 'record_video_note_screen.dart';
import 'user_profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
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

  Future<void> _drainIncoming(WsService ws) async {
    Message? m;
    while ((m = ws.takeIncomingFor(widget.peer.id)) != null) {
      final decrypted = await _decryptMessage(m!);
      await LocalDb.upsertMessage(decrypted, widget.peer.id);
      await LocalDb.updateChatLastMessage(widget.peer.id, decrypted);
      if (!mounted) return;
      setState(() => _messages.add(decrypted));
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
    );
  }

  /// Скачивает вложение (из кэша или сети), при необходимости распаковывает и расшифровывает (E2EE).
  Future<Uint8List?> _getAttachmentBytes(Message m) async {
    if (m.attachmentUrl == null || m.attachmentUrl!.isEmpty) return null;
    try {
      final name = m.attachmentFilename ?? 'file';
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
        _messages = fromDb;
        _loading = false;
      });
      _scrollToBottom();
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

  void _showMessageActions(Message m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    final others = chats.where((c) => c.peer.id != peerId).toList();
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
            ...others.map((chat) => ListTile(
              title: Text(chat.peer.displayName),
              subtitle: Text('@${chat.peer.username}'),
              onTap: () => Navigator.pop(ctx, chat),
            )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
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
        selected.peer.id,
        content,
        isForwarded: true,
        forwardFromSenderId: m.senderId,
        forwardFromDisplayName: fromName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Переслано в чат с ${selected.peer.displayName}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка пересылки')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    final replyToId = _replyingTo?.id;
    _text.clear();
    setState(() {
      _sending = true;
      _replyingTo = null;
    });
    String toSend = content;
    try {
      if (widget.peer.publicKey != null) {
        final encrypted = await _e2ee.encrypt(content, widget.peer.publicKey);
        if (encrypted != null) toSend = encrypted;
      }
      final api = Api(context.read<AuthService>().token);
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

  Future<void> _attachAndSend() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    final file = result.files.single;
    var bytes = Uint8List.fromList(file.bytes!);
    var encrypted = false;
    if (widget.peer.publicKey != null) {
      final enc = await _e2ee.encryptBytes(bytes, widget.peer.publicKey);
      if (enc != null) {
        bytes = enc;
        encrypted = true;
      }
    }
    final content = _text.text.trim();
    _text.clear();
    setState(() => _sending = true);
    try {
      final api = Api(context.read<AuthService>().token);
      final msg = await api.sendMessageWithFile(
        widget.peer.id,
        content,
        bytes,
        file.name,
        attachmentEncrypted: encrypted,
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
        SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка отправки файла')),
      );
    }
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
    );
    setState(() => _messages[idx] = newMsg);
  }

  Future<void> _startVoiceRecord() async {
    if (_sending || _isRecording) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Голосовые сообщения пока только на мобильных и ПК')),
      );
      return;
    }
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100), path: path);
      setState(() {
        _isRecording = true;
        _recordPath = path;
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
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordPath = null;
      });
      if (path == null || path.isEmpty) return;
      int durationSec = 0;
      try {
        final ap = AudioPlayer();
        await ap.setFilePath(path);
        final d = ap.duration;
        durationSec = d?.inSeconds ?? 0;
        await ap.dispose();
      } catch (_) {}
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
      setState(() => _sending = true);
      try {
        final api = Api(context.read<AuthService>().token);
        final msg = await api.sendVoiceMessage(widget.peer.id, voiceBytes, 'voice.m4a', durationSec, attachmentEncrypted: encrypted);
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
          SnackBar(content: Text(e is ApiException ? e.message : 'Ошибка отправки')),
        );
      }
    } catch (_) {}
  }

  Future<void> _openRecordVideoNote() async {
    if (_sending) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.peer.displayName),
            Text(
              '@${widget.peer.username}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Профиль',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(user: widget.peer),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Видеозвонок',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(peer: widget.peer, isIncoming: false),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          return Align(
                            alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showMessageActions(m),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: m.isMine
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
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
                                                m.replyToContent!,
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
                                    if (m.content.isNotEmpty)
                                      Text(
                                        m.content,
                                        style: m.isMine
                                            ? TextStyle(color: Theme.of(context).colorScheme.onPrimary)
                                            : null,
                                      ),
                                    if (m.hasAttachment) ...[
                                      if (m.content.isNotEmpty) const SizedBox(height: 8),
                                      _buildAttachment(m),
                                    ],
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(m.createdAt),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: m.isMine
                                          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                            _replyingTo!.content.length > 60 ? '${_replyingTo!.content.substring(0, 57)}...' : _replyingTo!.content,
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
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  enabled: !_sending,
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'file', child: Row(children: [Icon(Icons.attach_file), SizedBox(width: 12), Text('Файл')])),
                    const PopupMenuItem(value: 'poll', child: Row(children: [Icon(Icons.poll_outlined), SizedBox(width: 12), Text('Опрос')])),
                  ],
                  onSelected: (value) {
                    if (value == 'file') _attachAndSend();
                    if (value == 'poll') _createPoll();
                  },
                  tooltip: 'Прикрепить',
                  icon: const Icon(Icons.attach_file),
                ),
                GestureDetector(
                  onLongPressStart: (_) => _startVoiceRecord(),
                  onLongPressEnd: (_) => _stopVoiceRecord(),
                  child: IconButton(
                    onPressed: () {}, // запись только по долгому нажатию
                    icon: _isRecording
                        ? const Icon(Icons.stop_circle, color: Colors.red)
                        : const Icon(Icons.mic_none),
                    tooltip: 'Удерживайте для записи голосового',
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
                    onPressed: _send,
                    icon: const Icon(Icons.send),
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
        child: InkWell(
          onTap: () => _openUrl(url),
          child: Image.network(
            url,
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
      final path = await writeTempBytes(bytes, filename);
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть файл')));
    }
  }

  bool _isImageFilename(String name) {
    final parts = name.toLowerCase().split('.');
    final ext = parts.length > 1 ? parts.last : '';
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
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
