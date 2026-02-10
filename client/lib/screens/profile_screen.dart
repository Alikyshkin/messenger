import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

String _friendsCountLabel(BuildContext context, int? count) {
  if (count == null) return '—';
  if (count == 0) return context.tr('no_friends');
  if (count == 1) return context.tr('one_friend');
  if (count >= 2 && count <= 4) return context.tr('friends_2_4').replaceFirst('%s', '$count');
  return context.tr('friends_5_plus').replaceFirst('%s', '$count');
}

String _formatBirthday(BuildContext context, String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final months = [
    context.tr('jan'), context.tr('feb'), context.tr('mar'), context.tr('apr'),
    context.tr('may'), context.tr('jun'), context.tr('jul'), context.tr('aug'),
    context.tr('sep'), context.tr('oct'), context.tr('nov'), context.tr('dec'),
  ];
  final day = int.tryParse(parts[2]) ?? 0;
  final month = int.tryParse(parts[1]);
  final year = parts[0];
  if (month == null || month < 1 || month > 12) return iso;
  return '$day ${months[month - 1]} $year';
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthService>().refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final u = auth.user;
    if (u == null) return Scaffold(body: Center(child: Text(context.tr('not_authorized'))));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('profile')),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                        ? NetworkImage(u.avatarUrl!)
                        : null,
                    child: u.avatarUrl == null || u.avatarUrl!.isEmpty
                        ? Text(
                            u.displayName.isNotEmpty ? u.displayName[0].toUpperCase() : '@',
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    u.displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${u.username}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (u.bio != null && u.bio!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      u.bio!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (u.birthday != null && u.birthday!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cake_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(context.tr('friends')),
                  subtitle: Text(_friendsCountLabel(context, u.friendsCount)),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ContactsScreen()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(context.tr('settings')),
                  subtitle: Text(context.tr('settings_subtitle')),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(context.tr('logout')),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.tr('logout_confirm')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(context.tr('cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(context.tr('logout')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await auth.logout();
                      if (!context.mounted) return;
                      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

