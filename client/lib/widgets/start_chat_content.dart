import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../utils/app_page_route.dart';
import '../screens/chat_screen.dart';
import 'user_search_widget.dart';
import 'user_list_tile.dart';

/// Виджет содержимого экрана нового чата без Scaffold для встраивания в HomeScreen
class StartChatContent extends StatelessWidget {
  const StartChatContent({super.key});

  void _openChat(BuildContext context, User u) {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => ChatScreen(peer: u)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UserSearchWidget(
      labelText: context.tr('username'),
      hintText: context.tr('search_hint'),
      onUserSelected: (user) => _openChat(context, user),
      trailingBuilder: (user) => const Icon(Icons.message),
      minQueryLength: 2,
    );
  }
}
