import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';

/// Унифицированный виджет поиска пользователей
/// Используется для поиска пользователей для чата или добавления в друзья
class UserSearchWidget extends StatefulWidget {
  final String labelText;
  final String hintText;
  final Function(User) onUserSelected;
  final Widget Function(User)? trailingBuilder;
  final int minQueryLength;

  const UserSearchWidget({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.onUserSelected,
    this.trailingBuilder,
    this.minQueryLength = 2,
  });

  @override
  State<UserSearchWidget> createState() => _UserSearchWidgetState();
}

class _UserSearchWidgetState extends State<UserSearchWidget> {
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
    if (q.length < widget.minQueryLength) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: AppSpacing.inputPadding,
          child: TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: widget.labelText,
              border: const OutlineInputBorder(),
              suffixIcon: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(
                        width: AppSizes.loadingIndicatorSize,
                        height: AppSizes.loadingIndicatorSize,
                        child: const CircularProgressIndicator(
                          strokeWidth: AppSizes.loadingIndicatorStrokeWidth,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
            ),
            enableInteractiveSelection: true,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _search(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? EmptyStateWidget(message: widget.hintText)
              : ListView.builder(
                  padding: AppSpacing.listPadding,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final u = _results[i];
                    return UserListTile(
                      user: u,
                      trailing: widget.trailingBuilder?.call(u),
                      onTap: () => widget.onUserSelected(u),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
