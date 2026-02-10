import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/friend_request.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../widgets/skeleton.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<User> _contacts = [];
  List<FriendRequest> _requests = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = Api(auth.token);
      final results = await Future.wait([
        api.getContacts(),
        api.getFriendRequestsIncoming(),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = results[0] as List<User>;
        _requests = results[1] as List<FriendRequest>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Ошибка загрузки';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddContactScreen(),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? ListView.builder(
              itemCount: 12,
              itemBuilder: (_, __) => const SkeletonContactTile(),
            )
          : _error != null
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
              : _contacts.isEmpty && _requests.isEmpty
                  ? const Center(child: Text('Нет друзей.\nНажмите + чтобы добавить или отправить заявку.', textAlign: TextAlign.center))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        children: [
                          if (_requests.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                'Заявки в друзья',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            ..._requests.map((req) => ListTile(
                              title: Text(req.displayName),
                              subtitle: Text('@${req.username}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _reject(req.id),
                                    child: const Text('Отклонить'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _accept(req.id),
                                    child: const Text('Принять'),
                                  ),
                                ],
                              ),
                            )),
                            const Divider(height: 24),
                          ],
                          if (_contacts.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                              child: Text(
                                'Друзья',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            ..._contacts.map((u) => ListTile(
                              title: Text(u.displayName),
                              subtitle: Text('@${u.username}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.message),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(peer: u),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_outlined),
                                    tooltip: 'Удалить из друзей',
                                    onPressed: () => _confirmRemove(context, u),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Future<void> _accept(int requestId) async {
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).acceptFriendRequest(requestId);
      if (!mounted) return;
      _load();
    } catch (_) {}
  }

  Future<void> _reject(int requestId) async {
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).rejectFriendRequest(requestId);
      if (!mounted) return;
      _load();
    } catch (_) {}
  }

  Future<void> _confirmRemove(BuildContext context, User u) async {
    final auth = context.read<AuthService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из друзей?'),
        content: Text('Удалить ${u.displayName} из друзей?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api(auth.token).removeContact(u.id);
      if (!mounted) return;
      _load();
    } catch (_) {}
  }
}
