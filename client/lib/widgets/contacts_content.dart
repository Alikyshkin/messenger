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
  final NavigatorState? navigator;

  const ContactsContent({super.key, this.onFriendRequestChanged, this.navigator});

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
      final contacts = await api.getContacts();
      final requests = await api.getFriendRequestsIncoming();
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
        // Заголовок и кнопки действий
        Container(
          padding: AppSpacing.navigationPadding,
          height: AppSizes.appBarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  context.tr('contacts'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.people_alt_outlined),
                    tooltip: context.tr('possible_friends'),
                    onPressed: () async {
                      final nav = widget.navigator ?? Navigator.of(context);
                      await nav.push(
                        MaterialPageRoute(builder: (_) => const PossibleFriendsScreen()),
                      );
                      _load();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: context.tr('add_by_username'),
                    onPressed: () async {
                      final nav = widget.navigator ?? Navigator.of(context);
                      await nav.push(
                        MaterialPageRoute(builder: (_) => const AddContactScreen()),
                      );
                      _load();
                    },
                  ),
                ],
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
                                    onTap: () {
                                      final nav = widget.navigator ?? Navigator.of(context);
                                      nav.push(
                                        AppPageRoute(builder: (_) => UserProfileScreen(user: u)),
                                      );
                                    },
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.person_outline),
                                          onPressed: () {
                                            final nav = widget.navigator ?? Navigator.of(context);
                                            nav.push(
                                              AppPageRoute(builder: (_) => UserProfileScreen(user: u)),
                                            );
                                          },
                                          tooltip: context.tr('profile_tooltip'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.message_outlined),
                                          onPressed: () {
                                            final nav = widget.navigator ?? Navigator.of(context);
                                            nav.push(
                                              AppPageRoute(builder: (_) => ChatScreen(peer: u)),
                                            );
                                          },
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
