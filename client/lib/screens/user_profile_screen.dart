import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../utils/format_last_seen.dart';
import '../widgets/app_back_button.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'call_screen.dart';
import '../utils/user_action_logger.dart';

/// Профиль другого пользователя: отображается только количество друзей (не список).
class UserProfileScreen extends StatefulWidget {
  final User user;

  const UserProfileScreen({super.key, required this.user});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  User? _user;
  bool _loading = true;
  String? _error;
  bool _isContact = false;
  Set<int> _hideFromUserIds = {};

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final api = Api(auth.token);
      final u = await api.getUserProfile(widget.user.id);
      final contacts = await api.getContacts();
      final isContact = contacts.any((c) => c.id == u.id);
      Set<int> hideFrom = {};
      if (auth.user?.id != u.id) {
        hideFrom = (await api.getPrivacyHideFrom()).toSet();
      }
      if (!mounted) return;
      setState(() {
        _user = u;
        _isContact = isContact;
        _hideFromUserIds = hideFrom;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('load_error');
      });
    }
  }

  Future<void> _addContact() async {
    logUserAction('user_profile_add_contact', {
      'userId': (_user ?? widget.user).id,
    });
    final u = _user ?? widget.user;
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).addContact(u.username);
      if (!mounted) return;
      setState(() => _isContact = true);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : context.tr('connection_error'),
          ),
        ),
      );
    }
  }

  Future<void> _removeContact() async {
    logUserAction('user_profile_remove_contact', {
      'userId': (_user ?? widget.user).id,
    });
    final u = _user ?? widget.user;
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
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api(auth.token).removeContact(u.id);
      if (!mounted) return;
      setState(() => _isContact = false);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : context.tr('connection_error'),
          ),
        ),
      );
    }
  }

  String _friendsCountLabel(BuildContext context, int? count) {
    if (count == null) {
      return '—';
    }
    if (count == 0) {
      return context.tr('zero_friends');
    }
    if (count == 1) {
      return context.tr('one_friend');
    }
    if (count >= 2 && count <= 4) {
      return context.tr('friends_2_4').replaceFirst('%s', '$count');
    }
    return context.tr('friends_5_plus').replaceFirst('%s', '$count');
  }

  String _formatBirthday(BuildContext context, String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) {
      return iso;
    }
    final months = [
      context.tr('jan'),
      context.tr('feb'),
      context.tr('mar'),
      context.tr('apr'),
      context.tr('may'),
      context.tr('jun'),
      context.tr('jul'),
      context.tr('aug'),
      context.tr('sep'),
      context.tr('oct'),
      context.tr('nov'),
      context.tr('dec'),
    ];
    final day = int.tryParse(parts[2]) ?? 0;
    final month = int.tryParse(parts[1]);
    final year = parts[0];
    if (month == null || month < 1 || month > 12) {
      return iso;
    }
    return '$day ${months[month - 1]} $year';
  }

  Future<void> _toggleHideStatus() async {
    logUserAction('user_profile_toggle_hide_status', {
      'userId': (_user ?? widget.user).id,
    });
    final u = _user ?? widget.user;
    final auth = context.read<AuthService>();
    try {
      if (_hideFromUserIds.contains(u.id)) {
        await Api(auth.token).removePrivacyHideFrom(u.id);
        setState(() => _hideFromUserIds = {..._hideFromUserIds}..remove(u.id));
      } else {
        await Api(auth.token).addPrivacyHideFrom(u.id);
        setState(() => _hideFromUserIds = {..._hideFromUserIds, u.id});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : context.tr('connection_error'),
          ),
        ),
      );
    }
  }

  Future<void> _toggleBlock() async {
    logUserAction('user_profile_toggle_block', {
      'userId': (_user ?? widget.user).id,
    });
    final u = _user ?? widget.user;
    final auth = context.read<AuthService>();
    try {
      if (u.isBlocked == true) {
        await Api(auth.token).unblockUser(u.id);
      } else {
        await Api(auth.token).blockUser(u.id);
      }
      if (!mounted) return;
      setState(() => _user = u.copyWith(isBlocked: !(u.isBlocked ?? false)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : context.tr('connection_error'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user ?? widget.user;
    final myId = context.read<AuthService>().user?.id;
    final isOwnProfile = myId != null && myId == u.id;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(u.displayName),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: Text(context.tr('retry'))),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(u.displayName),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Загрузка...',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 24),
                Center(
                  child: UserAvatar(
                    user: u,
                    radius: 48,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    textStyle: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    showOnlineIndicator: true,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    u.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Center(
                  child: Text(
                    '@${u.username}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (u.isOnline == true ||
                    (u.lastSeen != null && u.lastSeen!.isNotEmpty)) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      formatLastSeen(context, u.lastSeen, u.isOnline),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: u.isOnline == true
                            ? Colors.green
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (u.bio != null && u.bio!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      u.bio!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (u.birthday != null && u.birthday!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cake_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatBirthday(context, u.birthday!),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(context.tr('friends')),
                  subtitle: Text(_friendsCountLabel(context, u.friendsCount)),
                ),
                const SizedBox(height: 24),
                if (!isOwnProfile) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_isContact)
                          FilledButton.icon(
                            onPressed: () {
                              logUserAction('user_profile_message', {
                                'userId': u.id,
                              });
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => ChatScreen(peer: u),
                                ),
                              );
                            },
                            icon: const Icon(Icons.message),
                            label: Text(context.tr('write')),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _addContact,
                            icon: const Icon(Icons.person_add),
                            label: Text(context.tr('add_friend')),
                          ),
                        if (_isContact)
                          OutlinedButton.icon(
                            onPressed: _removeContact,
                            icon: const Icon(Icons.person_remove_outlined),
                            label: Text(context.tr('remove_friend_tooltip')),
                          ),
                        if (_hideFromUserIds.contains(u.id))
                          OutlinedButton.icon(
                            onPressed: _toggleHideStatus,
                            icon: const Icon(Icons.visibility_outlined),
                            label: Text(context.tr('privacy_show_status')),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _toggleHideStatus,
                            icon: const Icon(Icons.visibility_off_outlined),
                            label: Text(context.tr('privacy_hide_status')),
                          ),
                        if (u.isBlocked == true)
                          OutlinedButton.icon(
                            onPressed: _toggleBlock,
                            icon: const Icon(Icons.block_outlined),
                            label: Text(context.tr('unblock_user')),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _toggleBlock,
                            icon: const Icon(Icons.block, size: 18),
                            label: Text(context.tr('block_user')),
                          ),
                        if (_isContact && u.isBlocked != true) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              logUserAction('user_profile_audio_call', {
                                'userId': u.id,
                              });
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => CallScreen(
                                    peer: u,
                                    isIncoming: false,
                                    isVideoCall: false,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.phone),
                            label: Text(context.tr('audio_call')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              logUserAction('user_profile_video_call', {
                                'userId': u.id,
                              });
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => CallScreen(
                                    peer: u,
                                    isIncoming: false,
                                    isVideoCall: true,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.videocam),
                            label: Text(context.tr('video_call')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
