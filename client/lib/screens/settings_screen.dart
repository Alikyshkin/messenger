import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../database/local_db.dart';
import '../l10n/app_localizations.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/attachment_cache.dart';
import '../services/locale_service.dart';
import '../services/theme_service.dart';
import '../widgets/app_back_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  String? _error;
  int _cacheSizeBytes = 0;
  /// День рождения в формате YYYY-MM-DD или null если не указан.
  String? _birthday;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthService>().user;
    if (u != null) {
      _displayNameController.text = u.displayName;
      _usernameController.text = u.username;
      _bioController.text = u.bio ?? '';
      _emailController.text = u.email ?? '';
      _phoneController.text = u.phone ?? '';
      _birthday = u.birthday;
    }
    _loadCacheSize();
  }

  /// Форматирует YYYY-MM-DD в "15 марта 1990" (или по локали).
  static String _formatBirthday(BuildContext context, String iso) {
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

  Future<void> _pickBirthday() async {
    DateTime initial = DateTime.now();
    if (_birthday != null && _birthday!.isNotEmpty) {
      final p = _birthday!.split('-');
      if (p.length == 3) {
        final y = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        final d = int.tryParse(p[2]);
        if (y != null && m != null && d != null) initial = DateTime(y, m, d);
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: context.tr('birthday_help'),
    );
    if (picked == null || !mounted) return;
    setState(() => _birthday = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
  }

  Future<void> _loadCacheSize() async {
    final size = await getAttachmentCacheSizeBytes();
    if (mounted) setState(() => _cacheSizeBytes = size);
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (current.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('enter_current_password'))));
      return;
    }
    if (newPw.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('new_password_min'))));
      return;
    }
    if (newPw != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('passwords_dont_match'))));
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await Api(auth.token).changePassword(current, newPw);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('password_changed'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('connection_error'))));
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final api = Api(auth.token);
      await api.patchMe(
        displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().replaceAll(RegExp(r'\D'), ''),
        birthday: _birthday ?? '',
      );
      await auth.refreshUser();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('profile_saved'))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('save_error');
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final filename = file.name;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await Api(auth.token).uploadAvatar(bytes, filename);
      await auth.refreshUser();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('photo_updated'))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('upload_photo_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final u = auth.user;
    if (u == null) return Scaffold(body: Center(child: Text(context.tr('not_authorized'))));

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('settings')),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: Text(context.tr('save')),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _loading ? null : _pickAndUploadAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.tr('tap_to_change_photo'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _displayNameController,
            decoration: InputDecoration(
              labelText: context.tr('display_name_label'),
              hintText: context.tr('display_name_hint'),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: context.tr('username_label'),
              hintText: context.tr('username_hint'),
              helperText: context.tr('username_helper'),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bioController,
            decoration: InputDecoration(
              labelText: context.tr('bio_label'),
              hintText: context.tr('bio_hint'),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            maxLength: 256,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: context.tr('email_label'),
              hintText: context.tr('email_hint_recovery'),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: context.tr('phone_label'),
              hintText: context.tr('phone_hint'),
              helperText: context.tr('phone_helper'),
            ),
            keyboardType: TextInputType.phone,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('birthday')),
            subtitle: Text(
              _birthday != null && _birthday!.isNotEmpty ? _formatBirthday(context, _birthday!) : context.tr('birthday_not_set'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_birthday != null && _birthday!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _loading ? null : () => setState(() => _birthday = ''),
                    tooltip: context.tr('reset'),
                  ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: _loading ? null : _pickBirthday,
                  tooltip: context.tr('pick_date'),
                ),
              ],
            ),
            onTap: _loading ? null : _pickBirthday,
          ),
          const SizedBox(height: 32),
          const Divider(),
          Text(
            context.tr('appearance'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('dark_theme'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(context.tr('theme_light')),
                        icon: const Icon(Icons.light_mode_outlined, size: 20),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(context.tr('theme_dark')),
                        icon: const Icon(Icons.dark_mode_outlined, size: 20),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(context.tr('theme_system')),
                        icon: const Icon(Icons.brightness_auto_outlined, size: 20),
                      ),
                    ],
                    selected: {context.watch<ThemeService>().themeMode},
                    onSelectionChanged: _loading
                        ? null
                        : (Set<ThemeMode> selected) {
                            context.read<ThemeService>().setThemeMode(selected.first);
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.language),
            title: Text(context.tr('language')),
            subtitle: Text(
              (context.watch<LocaleService>().locale?.languageCode == 'en')
                  ? context.tr('language_en')
                  : context.tr('language_ru'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _loading ? null : _showLanguagePicker,
          ),
          const SizedBox(height: 32),
          const Divider(),
          Text(
            context.tr('change_password_section'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _currentPasswordController,
            decoration: InputDecoration(
              labelText: context.tr('current_password'),
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            decoration: InputDecoration(
              labelText: context.tr('new_password'),
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            decoration: InputDecoration(
              labelText: context.tr('confirm_password'),
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _changePassword,
            icon: const Icon(Icons.lock_reset, size: 20),
            label: Text(context.tr('change_password_btn')),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            context.tr('cache_section'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('cache_description'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatBytes(_cacheSizeBytes),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _showClearCacheByChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: Text(context.tr('clear_cache_by_chat')),
              ),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _clearAllCache,
                icon: const Icon(Icons.delete_sweep, size: 20),
                label: Text(context.tr('clear_all_cache')),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Divider(),
          Text(
            context.tr('danger_zone'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('delete_account_confirm_body'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loading ? null : _deleteAccount,
                    icon: const Icon(Icons.person_remove, size: 22),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(context.tr('delete_account')),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker() {
    final localeService = context.read<LocaleService>();
    final isEn = localeService.locale?.languageCode == 'en';
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.check, color: !isEn ? Theme.of(ctx).colorScheme.primary : Colors.transparent),
              title: Text(context.tr('language_ru')),
              onTap: () {
                localeService.setLocale(const Locale('ru'));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.check, color: isEn ? Theme.of(ctx).colorScheme.primary : Colors.transparent),
              title: Text(context.tr('language_en')),
              onTap: () {
                localeService.setLocale(const Locale('en'));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_account_confirm_title')),
        content: Text(context.tr('delete_account_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await Api(auth.token).deleteAccount();
      if (!mounted) return;
      await auth.logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('account_deleted'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('connection_error'))));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Future<void> _showClearCacheByChat() async {
    final chats = await LocalDb.getChats();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('clear_cache_for_chat_title'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (_, i) {
                  final chat = chats[i];
                  final peer = chat.peer;
                  if (peer == null) return const SizedBox.shrink();
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: peer.avatarUrl != null && peer.avatarUrl!.isNotEmpty
                          ? NetworkImage(peer.avatarUrl!)
                          : null,
                      child: peer.avatarUrl == null || peer.avatarUrl!.isEmpty
                          ? Text((peer.displayName.isNotEmpty ? peer.displayName[0] : '@').toUpperCase())
                          : null,
                    ),
                    title: Text(peer.displayName.isNotEmpty ? peer.displayName : peer.username),
                    subtitle: Text('@${peer.username}'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await clearAttachmentCacheForChat(peer.id);
                      await _loadCacheSize();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('cache_cleared_for').replaceFirst('%s', peer.displayName.isNotEmpty ? peer.displayName : peer.username))),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearAllCache() async {
    await clearAllAttachmentCache();
    await _loadCacheSize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('all_cache_cleared'))));
    }
  }
}
