import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../models/friend_request.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import 'skeleton.dart';
import 'user_avatar.dart';
import 'user_list_tile.dart';
import 'section_card.dart';
import 'error_state_widget.dart';
import 'empty_state_widget.dart';
import '../screens/add_contact_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/possible_friends_screen.dart';
import '../screens/user_profile_screen.dart';

/// Виджет содержимого экрана контактов без Scaffold для встраивания в HomeScreen
class ContactsContent extends StatefulWidget {
  final VoidCallback? onFriendRequestChanged;

  const ContactsContent({super.key, this.onFriendRequestChanged});

  @override
  State<ContactsContent> createState() => _ContactsContentState();
}

class _ContactsContentState extends State<ContactsContent> {
  List<User> _contacts = [];
  List<FriendRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final api = Api(auth.token);
      final [contacts, requests] = await Future.wait([
        api.getContacts(),
        api.getFriendRequestsIncoming(),
      ]);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _requests = requests;
        _loading = false;
      });
      widget.onFriendRequestChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('error');
      });
    }
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
        content: Text(context.tr('remove_friend_body').replaceFirst('%s', u.displayName)),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Кнопки действий в AppBar
        Container(
          padding: AppSpacing.navigationPadding,
          height: AppSizes.appBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.people_alt_outlined),
                tooltip: context.tr('possible_friends'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PossibleFriendsScreen()),
                  );
                  _load();
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: context.tr('add_by_username'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddContactScreen()),
                  );
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? ListView.builder(
                  padding: AppSpacing.listPadding,
                  itemCount: 12,
                  itemBuilder: (_, __) => const Card(child: SkeletonContactTile()),
                )
              : _error != null
                  ? ErrorStateWidget(
                      message: _error!,
                      onRetry: _load,
                      retryLabel: context.tr('retry'),
                    )
                  : _contacts.isEmpty && _requests.isEmpty
                      ? EmptyStateWidget(
                          message: context.tr('no_friends_add_hint'),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: AppSpacing.listPadding,
                            children: [
                              Card(
                                child: ListTile(
                                  contentPadding: AppSpacing.listItemPadding,
                                  leading: CircleAvatar(
                                    radius: AppSizes.avatarMD,
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.people_alt_outlined,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                      MaterialPageRoute(builder: (_) => const PossibleFriendsScreen()),
                                    );
                                    _load();
                                  },
                                ),
                              ),
                              AppSpacing.spacingVerticalMD,
                              if (_requests.isNotEmpty) ...[
                                SectionCard(
                                  title: context.tr('friend_requests'),
                                  children: _requests.map((req) => ListTile(
                                    contentPadding: AppSpacing.listItemPadding,
                                    leading: CircleAvatar(
                                      radius: AppSizes.avatarMD,
                                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                      child: Text(
                                        req.displayName.isNotEmpty ? req.displayName[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                        AppSpacing.spacingHorizontalSM,
                                        FilledButton(
                                          onPressed: () => _accept(req.id),
                                          child: Text(context.tr('accept')),
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                                AppSpacing.spacingVerticalMD,
                              ],
                              if (_contacts.isNotEmpty) ...[
                                SectionCard(
                                  title: context.tr('friends'),
                                  children: _contacts.map((u) => UserListTile(
                                    user: u,
                                    avatarRadius: AppSizes.avatarMD,
                                    onTap: () => Navigator.of(context).push(
                                      AppPageRoute(builder: (_) => UserProfileScreen(user: u)),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.person_outline),
                                          onPressed: () => Navigator.of(context).push(
                                            AppPageRoute(builder: (_) => UserProfileScreen(user: u)),
                                          ),
                                          tooltip: context.tr('profile_tooltip'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.message_outlined),
                                          onPressed: () => Navigator.of(context).push(
                                            AppPageRoute(builder: (_) => ChatScreen(peer: u)),
                                          ),
                                          tooltip: context.tr('write'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.person_remove_outlined),
                                          tooltip: context.tr('remove_friend_tooltip'),
                                          onPressed: () => _confirmRemove(context, u),
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
        ),
      ],
    );
  }
}
