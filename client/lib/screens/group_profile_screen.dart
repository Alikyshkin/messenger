import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/group.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import 'group_chat_screen.dart';

class GroupProfileScreen extends StatefulWidget {
  final Group group;

  const GroupProfileScreen({super.key, required this.group});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  Group? _group;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final g = await Api(auth.token).getGroup(widget.group.id);
      if (!mounted) return;
      setState(() {
        _group = g;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('leave_group')),
        content: Text(context.tr('leave_group_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('leave_group')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final auth = context.read<AuthService>();
    try {
      await Api(auth.token).removeGroupMember(widget.group.id, auth.user!.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : context.tr('error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _group ?? widget.group;
    final me = context.watch<AuthService>().user?.id;
    final isAdmin = g.myRole == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: g.avatarUrl != null && g.avatarUrl!.isNotEmpty
                  ? NetworkImage(g.avatarUrl!)
                  : null,
              child: g.avatarUrl == null || g.avatarUrl!.isEmpty
                  ? Icon(
                      Icons.group,
                      size: 48,
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              g.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.tr('members_count').replaceFirst('%s', '${g.memberCount ?? g.members?.length ?? 0}'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(context.tr('group_call')),
            subtitle: Text(
              context.tr('group_call_coming'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('group_call_coming'))),
              );
            },
          ),
          if (g.members != null && g.members!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.tr('friends'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...g.members!.map((member) => ListTile(
                  leading: CircleAvatar(
                    backgroundImage: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                        ? NetworkImage(member.avatarUrl!)
                        : null,
                    child: member.avatarUrl == null || member.avatarUrl!.isEmpty
                        ? Text((member.displayName.isNotEmpty ? member.displayName[0] : '@').toUpperCase())
                        : null,
                  ),
                  title: Row(
                    children: [
                      Text(member.displayName),
                      if (member.role == 'admin')
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '(admin)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text('@${member.username}'),
                )),
          ],
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _loading ? null : _leaveGroup,
            icon: const Icon(Icons.exit_to_app, size: 20),
            label: Text(context.tr('leave_group')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
