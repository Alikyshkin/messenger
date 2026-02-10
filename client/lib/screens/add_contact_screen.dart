import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../widgets/app_back_button.dart';
import 'chat_screen.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _query = TextEditingController();
  List<User> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final api = Api(context.read<AuthService>().token);
      final list = await api.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : context.tr('error');
        _searching = false;
      });
    }
  }

  Future<void> _add(User u) async {
    setState(() => _error = null);
    try {
      final added = await Api(context.read<AuthService>().token).addContact(u.username);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('request_sent'))),
      );
      Navigator.of(context).push(
        AppPageRoute(builder: (_) => ChatScreen(peer: added)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: Text(context.tr('add_friend'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                labelText: context.tr('username'),
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _search,
                      ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(context.tr('search_hint')))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final u = _results[i];
                      return ListTile(
                        title: Text(u.displayName),
                        subtitle: Text('@${u.username}'),
                        trailing: FilledButton(
                          onPressed: () => _add(u),
                          child: Text(context.tr('add')),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
