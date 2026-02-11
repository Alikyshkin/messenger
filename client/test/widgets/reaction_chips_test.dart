import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/message.dart';

/// Минимальный виджет для отображения реакций (как в чате).
class ReactionChips extends StatelessWidget {
  final List<MessageReaction> reactions;

  const ReactionChips({super.key, required this.reactions});

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: reactions.map((r) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${r.emoji} ${r.count > 1 ? r.count : ''}'),
        );
      }).toList(),
    );
  }
}

void main() {
  group('ReactionChips', () {
    testWidgets('renders nothing when reactions empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReactionChips(reactions: [])),
        ),
      );
      expect(find.byType(ReactionChips), findsOneWidget);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders one reaction with count', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionChips(
              reactions: [
                MessageReaction(emoji: '👍', userIds: [1, 2]),
              ],
            ),
          ),
        ),
      );
      expect(find.text('👍 2'), findsOneWidget);
    });

    testWidgets('renders multiple reaction chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionChips(
              reactions: [
                MessageReaction(emoji: '👍', userIds: [1]),
                MessageReaction(emoji: '❤️', userIds: [2, 3]),
              ],
            ),
          ),
        ),
      );
      expect(find.text('👍 '), findsOneWidget);
      expect(find.text('❤️ 2'), findsOneWidget);
    });
  });
}
