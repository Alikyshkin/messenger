import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../utils/app_page_route.dart';
import '../utils/user_action_logger.dart';
import '../screens/chat_screen.dart';
import '../styles/app_spacing.dart';
import '../styles/app_sizes.dart';
import 'user_search_widget.dart';

/// Виджет содержимого экрана нового чата без Scaffold для встраивания в HomeScreen
class StartChatContent extends StatelessWidget {
  final NavigatorState? navigator;

  const StartChatContent({super.key, this.navigator});

  void _openChat(BuildContext context, User u) {
    logUserAction('start_chat_content_open', {'userId': u.id});
    final nav = navigator ?? Navigator.of(context);
    nav.push(AppPageRoute(builder: (_) => ChatScreen(peer: u)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Заголовок
        Container(
          padding: AppSpacing.navigationPadding,
          height: AppSizes.appBarHeight,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  context.tr('new_chat'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: UserSearchWidget(
            labelText: context.tr('username'),
            hintText: context.tr('search_hint'),
            onUserSelected: (user) => _openChat(context, user),
            trailingBuilder: (user) => const Icon(Icons.message),
            minQueryLength: 2,
          ),
        ),
      ],
    );
  }
}
