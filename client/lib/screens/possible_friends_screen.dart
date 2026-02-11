import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../widgets/app_back_button.dart';
import 'user_profile_screen.dart';

/// Нормализация номера: только цифры (как на сервере).
String _normalizePhone(String s) {
  return s.replaceAll(RegExp(r'\D'), '');
}

class PossibleFriendsScreen extends StatefulWidget {
  const PossibleFriendsScreen({super.key});

  @override
  State<PossibleFriendsScreen> createState() => _PossibleFriendsScreenState();
}

class _PossibleFriendsScreenState extends State<PossibleFriendsScreen> {
  List<User> _users = [];
  Set<int> _contactIds = {};
  Set<int> _pendingIds = {};
  bool _loading = true;
  String? _error;
  bool _syncing = false;

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
      final api = Api(auth.token);
      final contacts = await api.getContacts();
      final incoming = await api.getFriendRequestsIncoming();
      final outgoingIds = await _getOutgoingRequestIds(api);
      if (!mounted) {
        return;
      }
      setState(() {
        _contactIds = contacts.map((u) => u.id).toSet();
        _pendingIds = {...outgoingIds, ...incoming.map((r) => r.fromUserId)};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e is ApiException ? e.message : context.tr('load_error');
        _loading = false;
      });
    }
  }

  Future<Set<int>> _getOutgoingRequestIds(Api api) async {
    try {
      final r = await api.getFriendRequestsOutgoing();
      return r.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _syncContacts() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('contacts_permission')),
          action: SnackBarAction(
            label: context.tr('settings'),
            onPressed: openAppSettings,
          ),
        ),
      );
      return;
    }
    setState(() => _syncing = true);
    if (!mounted) return;
    try {
      final auth = context.read<AuthService>();
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final phones = <String>{};
      for (final c in contacts) {
        for (final p in c.phones) {
          final norm = _normalizePhone(p.number);
          if (norm.length >= 10) {
            phones.add(norm);
          }
        }
      }
      if (phones.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('no_phones_in_contacts'))),
        );
        return;
      }
      final api = Api(auth.token);
      final found = await api.findUsersByPhones(phones.toList());
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = found
            .where(
              (u) => !_contactIds.contains(u.id) && !_pendingIds.contains(u.id),
            )
            .toList();
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Ошибка синхронизации'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load().then((_) {
        if (mounted && _users.isEmpty && !_loading && _error == null) {
          _syncContacts();
        }
      });
    });
  }

  Future<void> _addFriend(User u) async {
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).addContact(u.username);
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingIds.add(u.id);
        _users = _users.where((x) => x.id != u.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('request_sent_to').replaceFirst('%s', u.displayName),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('possible_friends')),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: context.tr('sync_contacts'),
              onPressed: _syncContacts,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: Text(context.tr('retry')),
                    ),
                  ],
                ),
              ),
            )
          : _users.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('possible_friends_empty'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _syncing ? null : _syncContacts,
                      icon: const Icon(Icons.sync, size: 20),
                      label: Text(context.tr('sync_contacts')),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await _load();
                if (mounted) {
                  _syncContacts();
                }
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _users.length,
                itemBuilder: (context, i) {
                  final u = _users[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage:
                            u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                            ? NetworkImage(u.avatarUrl!)
                            : null,
                        child: u.avatarUrl == null || u.avatarUrl!.isEmpty
                            ? Text(
                                u.displayName.isNotEmpty
                                    ? u.displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        u.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '@${u.username}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      trailing: FilledButton(
                        onPressed: () => _addFriend(u),
                        child: Text(context.tr('add')),
                      ),
                      onTap: () => Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => UserProfileScreen(user: u),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
