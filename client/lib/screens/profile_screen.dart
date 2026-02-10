import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

String _friendsCountLabel(int? count) {
  if (count == null) return '—';
  if (count == 0) return 'Нет друзей';
  if (count == 1) return '1 друг';
  if (count >= 2 && count <= 4) return '$count друга';
  return '$count друзей';
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
    if (u == null) return const Scaffold(body: Center(child: Text('Не авторизован')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
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
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage: u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                  ? NetworkImage(u.avatarUrl!)
                  : null,
              child: u.avatarUrl == null || u.avatarUrl!.isEmpty
                  ? Text(
                      u.displayName.isNotEmpty ? u.displayName[0].toUpperCase() : '@',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : null,
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
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text('Друзья'),
            subtitle: Text(_friendsCountLabel(u.friendsCount)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Настройки'),
            subtitle: const Text('Имя, username, фото, описание'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Выйти'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Выйти?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Выйти'),
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
    );
  }
}

