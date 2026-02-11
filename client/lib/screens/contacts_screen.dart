import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../models/friend_request.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../widgets/app_back_button.dart';
import '../widgets/skeleton.dart';
import '../widgets/user_avatar.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';
import 'possible_friends_screen.dart';
import 'user_profile_screen.dart';

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
    if (!auth.isLoggedIn) {
      return;
    }
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
        _error = e is ApiException ? e.message : context.tr('load_error');
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('contacts')),
        backgroundColor: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primary,
        foregroundColor: isDark ? theme.colorScheme.onSurface : Colors.white,
        actionsIconTheme: IconThemeData(
          color: isDark ? theme.colorScheme.onSurface : Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: context.tr('possible_friends'),
            onPressed: () async {
              await Navigator.of(context).push(
                AppPageRoute(builder: (_) => const PossibleFriendsScreen()),
              );
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('add_by_username'),
            onPressed: () async {
              await Navigator.of(
                context,
              ).push(AppPageRoute(builder: (_) => const AddContactScreen()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: 12,
              itemBuilder: (_, _) => const Card(child: SkeletonContactTile()),
            )
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
          : _contacts.isEmpty && _requests.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.tr('no_friends_add_hint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.people_alt_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        context.tr('possible_friends'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.tr('possible_friends_subtitle'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PossibleFriendsScreen(),
                          ),
                        );
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_requests.isNotEmpty) ...[
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              context.tr('friend_requests'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                          ..._requests.map(
                            (req) => ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: Text(
                                  req.displayName.isNotEmpty
                                      ? req.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              title: Text(
                                req.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '@${req.username}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _reject(req.id),
                                    child: Text(context.tr('reject')),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _accept(req.id),
                                    child: Text(context.tr('accept')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_contacts.isNotEmpty) ...[
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              context.tr('friends'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ),
                          ..._contacts.map(
                            (u) => ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: UserAvatar(
                                user: u,
                                radius: 24,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                textStyle: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              title: Text(
                                u.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '@${u.username}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: () => Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => UserProfileScreen(user: u),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.person_outline),
                                    onPressed: () => Navigator.of(context).push(
                                      AppPageRoute(
                                        builder: (_) =>
                                            UserProfileScreen(user: u),
                                      ),
                                    ),
                                    tooltip: context.tr('profile_tooltip'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.message_outlined),
                                    onPressed: () => Navigator.of(context).push(
                                      AppPageRoute(
                                        builder: (_) => ChatScreen(peer: u),
                                      ),
                                    ),
                                    tooltip: context.tr('write'),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                    tooltip: context.tr(
                                      'remove_friend_tooltip',
                                    ),
                                    onPressed: () => _confirmRemove(context, u),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
        title: Text(context.tr('remove_friend_title')),
        content: Text(
          context.tr('remove_friend_body').replaceFirst('%s', u.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    try {
      await Api(auth.token).removeContact(u.id);
      if (!mounted) return;
      _load();
    } catch (_) {}
  }
}
