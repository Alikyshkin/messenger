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

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  List<User> _contacts = [];
  List<FriendRequest> _incoming = [];
  List<OutgoingFriendRequest> _outgoing = [];
  bool _loading = true;
  String? _error;

  late final TabController _requestsTabController;

  @override
  void initState() {
    super.initState();
    _requestsTabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _requestsTabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final hasData =
        _contacts.isNotEmpty || _incoming.isNotEmpty || _outgoing.isNotEmpty;
    setState(() {
      if (!hasData) _loading = true;
      _error = null;
    });
    try {
      final api = Api(auth.token);
      final results = await Future.wait([
        api.getContacts(),
        api.getFriendRequestsIncoming(),
        api.getFriendRequestsOutgoing(),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = results[0] as List<User>;
        _incoming = results[1] as List<FriendRequest>;
        _outgoing = results[2] as List<OutgoingFriendRequest>;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('contacts')),
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
              await Navigator.of(context).push(
                AppPageRoute(builder: (_) => const AddContactScreen()),
              );
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
                      style: TextStyle(color: theme.colorScheme.error),
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  // "Возможные друзья" — быстрый доступ
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.people_alt_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
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
                          color: theme.colorScheme.onSurfaceVariant,
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

                  // Секция заявок (только если есть хотя бы одна)
                  if (_incoming.isNotEmpty || _outgoing.isNotEmpty) ...[
                    _RequestsSection(
                      incoming: _incoming,
                      outgoing: _outgoing,
                      tabController: _requestsTabController,
                      onAccept: _accept,
                      onReject: _reject,
                      onCancel: _cancel,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Список друзей
                  if (_contacts.isNotEmpty) ...[
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                Text(
                                  context.tr('friends'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_contacts.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
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
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                textStyle: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
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
                                  color: theme.colorScheme.onSurfaceVariant,
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
                                    tooltip: context.tr('remove_friend_tooltip'),
                                    onPressed: () =>
                                        _confirmRemove(context, u),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_incoming.isEmpty && _outgoing.isEmpty) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          context.tr('no_friends_add_hint'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
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

  Future<void> _cancel(int requestId) async {
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).cancelFriendRequest(requestId);
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
    if (ok != true || !mounted) return;
    try {
      await Api(auth.token).removeContact(u.id);
      if (!mounted) return;
      _load();
    } catch (_) {}
  }
}

/// Секция заявок с вкладками «Входящие / Исходящие»
class _RequestsSection extends StatelessWidget {
  const _RequestsSection({
    required this.incoming,
    required this.outgoing,
    required this.tabController,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  final List<FriendRequest> incoming;
  final List<OutgoingFriendRequest> outgoing;
  final TabController tabController;
  final void Function(int requestId) onAccept;
  final void Function(int requestId) onReject;
  final void Function(int requestId) onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  context.tr('friend_requests'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (incoming.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${incoming.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          TabBar(
            controller: tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.tr('incoming_requests')),
                    if (incoming.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${incoming.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.tr('outgoing_requests')),
                    if (outgoing.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${outgoing.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(
            // Высота зависит от числа элементов, но не менее 60
            height: _listHeight(tabController, incoming.length, outgoing.length),
            child: TabBarView(
              controller: tabController,
              children: [
                _IncomingList(requests: incoming, onAccept: onAccept, onReject: onReject),
                _OutgoingList(requests: outgoing, onCancel: onCancel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _listHeight(TabController tab, int inLen, int outLen) {
    const itemH = 80.0;
    const emptyH = 72.0;
    final inH = inLen == 0 ? emptyH : inLen * itemH;
    final outH = outLen == 0 ? emptyH : outLen * itemH;
    // Показываем высоту текущей вкладки, но анимируем через LayoutBuilder
    // Для простоты берём максимум
    return (inH > outH ? inH : outH).clamp(emptyH, 400.0);
  }
}

class _IncomingList extends StatelessWidget {
  const _IncomingList({
    required this.requests,
    required this.onAccept,
    required this.onReject,
  });

  final List<FriendRequest> requests;
  final void Function(int) onAccept;
  final void Function(int) onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '—',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final req = requests[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              req.displayName.isNotEmpty
                  ? req.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(
            req.displayName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '@${req.username}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => onReject(req.id),
                child: Text(context.tr('reject')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => onAccept(req.id),
                child: Text(context.tr('accept')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OutgoingList extends StatelessWidget {
  const _OutgoingList({required this.requests, required this.onCancel});

  final List<OutgoingFriendRequest> requests;
  final void Function(int) onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '—',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final req = requests[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              req.displayName.isNotEmpty
                  ? req.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(
            req.displayName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '@${req.username}  ·  ${context.tr('pending_confirmation')}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          trailing: TextButton(
            onPressed: () => onCancel(req.id),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(context.tr('cancel_request')),
          ),
        );
      },
    );
  }
}
