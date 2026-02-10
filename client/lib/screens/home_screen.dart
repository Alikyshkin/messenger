import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/local_db.dart';
import '../models/chat.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChatPreview> _chats = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WsService>().connect(context.read<AuthService>().token);
      _load();
    });
    Connectivity().onConnectivityChanged.listen((_) {
      if (!mounted) return;
      _flushOutbox();
    });
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
        await LocalDb.upsertChat(chat);
      }
      final merged = await LocalDb.getChats();
      if (!mounted) return;
      setState(() {
        _chats = merged;
        _loading = false;
      });
      _flushOutbox();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Ошибка загрузки';
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

  String _previewContent(String content) {
    if (content.startsWith('e2ee:')) return 'Сообщение';
    return content;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ContactsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _chats.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _chats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 16),
                        TextButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  )
                : _chats.isEmpty
                    ? const Center(child: Text('Нет чатов.\nДобавьте контакт и напишите ему.', textAlign: TextAlign.center))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (context, i) {
                          final c = _chats[i];
                          return ListTile(
                            title: Text(c.peer.displayName),
                            subtitle: c.lastMessage != null
                                ? Text(
                                    c.lastMessage!.isMine
                                        ? 'Вы: ${c.lastMessage!.isPoll ? 'Опрос: ' : ''}${_previewContent(c.lastMessage!.content)}'
                                        : '${c.lastMessage!.isPoll ? 'Опрос: ' : ''}${_previewContent(c.lastMessage!.content)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(peer: c.peer),
                                ),
                              );
                              _load();
                            },
                          );
                        },
                      ),
      ),
    );
  }
}
