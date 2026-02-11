import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../widgets/app_back_button.dart';
import '../utils/app_page_route.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  List<User> _contacts = [];
  final Set<int> _selectedIds = {};
  Uint8List? _avatarBytes;
  String? _avatarFilename;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final list = await Api(auth.token).getContacts();
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('error');
      });
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) return;
    setState(() {
      _avatarBytes = Uint8List.fromList(file.bytes!);
      _avatarFilename = file.name;
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('group_name_hint'))),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('select_at_least_one_member'))),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final group = await Api(auth.token).createGroup(
        name,
        _selectedIds.toList(),
        avatarBytes: _avatarBytes,
        avatarFilename: _avatarFilename,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        AppPageRoute(builder: (_) => GroupChatScreen(group: group)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : context.tr('error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('create_group')),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _create,
              child: Text(context.tr('create')),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _loading ? null : _pickPhoto,
            child: Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: _avatarBytes != null
                        ? MemoryImage(_avatarBytes!)
                        : null,
                    child: _avatarBytes == null
                        ? Icon(
                            Icons.camera_alt,
                            size: 48,
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                          )
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 20, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.tr('tap_to_set_photo'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: context.tr('group_name'),
              hintText: context.tr('group_name_hint'),
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            enableInteractiveSelection: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '${context.tr('participants')} (${_selectedIds.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ..._contacts.map((u) {
            final selected = _selectedIds.contains(u.id);
            return CheckboxListTile(
              value: selected,
              onChanged: _loading
                  ? null
                  : (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(u.id);
                        } else {
                          _selectedIds.remove(u.id);
                        }
                      });
                    },
              title: Text(u.displayName),
              subtitle: Text('@${u.username}'),
              secondary: CircleAvatar(
                backgroundImage: u.avatarUrl != null && u.avatarUrl!.isNotEmpty
                    ? NetworkImage(u.avatarUrl!)
                    : null,
                child: u.avatarUrl == null || u.avatarUrl!.isEmpty
                    ? Text((u.displayName.isNotEmpty ? u.displayName[0] : '@').toUpperCase())
                    : null,
              ),
            );
          }),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('create_group')),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
