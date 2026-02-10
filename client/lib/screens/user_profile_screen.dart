import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
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
    if (_user!.friendsCount == null) _load();
    else _loading = false;
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
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
        _error = e is ApiException ? e.message : 'Ошибка загрузки';
      });
    }
  }

  static String _friendsCountLabel(int? count) {
    if (count == null) return '—';
    if (count == 0) return '0 друзей';
    if (count == 1) return '1 друг';
    if (count >= 2 && count <= 4) return '$count друга';
    return '$count друзей';
  }

  @override
  Widget build(BuildContext context) {
    final u = _user ?? widget.user;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(u.displayName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(u.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            tooltip: 'Написать',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => ChatScreen(peer: u)),
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
                  title: const Text('Друзья'),
                  subtitle: Text(_friendsCountLabel(u.friendsCount)),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => ChatScreen(peer: u)),
                      );
                    },
                    icon: const Icon(Icons.message),
                    label: const Text('Написать'),
                  ),
                ),
              ],
            ),
    );
  }
}
