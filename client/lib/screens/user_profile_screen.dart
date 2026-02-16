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

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    if (_user!.friendsCount == null) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      return;
    }
    setState(() => _loading = true);
    try {
      final u = await Api(auth.token).getUserProfile(widget.user.id);
      if (!mounted) return;
      setState(() {
        _user = u;
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

  @override
  Widget build(BuildContext context) {
    final u = _user ?? widget.user;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            tooltip: context.tr('write'),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                AppPageRoute(builder: (_) => ChatScreen(peer: u)),
              );
            },
          ),
        ],
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
                if (u.isOnline == true || (u.lastSeen != null && u.lastSeen!.isNotEmpty)) ...[
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        AppPageRoute(builder: (_) => ChatScreen(peer: u)),
                      );
                    },
                    icon: const Icon(Icons.message),
                    label: Text(context.tr('write')),
                  ),
                ),
              ],
            ),
    );
  }
}
