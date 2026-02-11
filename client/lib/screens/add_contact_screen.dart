import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../widgets/app_back_button.dart';
import '../widgets/user_search_widget.dart';
import '../widgets/user_list_tile.dart';
import 'chat_screen.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  String? _error;

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
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('add_friend')),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: UserSearchWidget(
              labelText: context.tr('username'),
              hintText: context.tr('search_hint'),
              onUserSelected: _add,
              trailingBuilder: (user) => FilledButton(
                onPressed: () => _add(user),
                child: Text(context.tr('add')),
              ),
              minQueryLength: 2,
            ),
          ),
        ],
      ),
    );
  }
}
