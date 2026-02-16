import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../models/search_result.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../utils/app_page_route.dart';
import '../utils/format_date.dart';
import '../widgets/app_back_button.dart';

/// Экран поиска по сообщениям в чатах.
class SearchChatsScreen extends StatefulWidget {
  const SearchChatsScreen({super.key});

  @override
  State<SearchChatsScreen> createState() => _SearchChatsScreenState();
}

class _SearchChatsScreenState extends State<SearchChatsScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<SearchMessageItem> _results = [];
  bool _loading = false;
  String? _error;
  static const int _minQueryLength = 2;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < _minQueryLength) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      final api = Api(auth.token);

      final personal = await api.searchMessages(q, limit: 30);
      final group = await api.searchGroupMessages(q, limit: 30);

      if (!mounted) return;

      final combined = <SearchMessageItem>[
        ...personal.data,
        ...group.data,
      ];
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _results = combined;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : context.tr('connection_error');
        _loading = false;
      });
    }
  }

  void _openChat(SearchMessageItem item) {
    if (item.isGroup && item.groupId != null) {
      context.push('/group/${item.groupId}');
    } else if (item.peerId != null) {
      context.push('/chat/${item.peerId}');
    }
  }

  String _previewContent(SearchMessageItem item) {
    if (item.content.startsWith('e2ee:')) return context.tr('message');
    if (item.content.length > 80) return '${item.content.substring(0, 77)}…';
    return item.content;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.tr('search_in_chats_hint'),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _loading ? null : _search,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            TextButton(onPressed: _search, child: Text(context.tr('retry'))),
          ],
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final q = _controller.text.trim();
    if (q.isEmpty || q.length < _minQueryLength) {
      return Center(
        child: Text(
          context.tr('search_in_chats_enter_query'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.tr('search_no_results'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final item = _results[i];
        final title = item.isGroup
            ? '${item.groupName ?? ''} • ${item.senderDisplayName ?? ''}'
            : (item.peerDisplayName ?? 'Пользователь');
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              item.isGroup ? Icons.group : Icons.person,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _previewContent(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          trailing: Text(
            formatMessageDate(item.createdAt),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          onTap: () => _openChat(item),
        );
      },
    );
  }
}
