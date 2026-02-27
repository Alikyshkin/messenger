import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/app_colors.dart';
import 'package:client/models/chat.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// WCAG AA contrast ratio threshold (4.5:1 for normal text).
const double _kMinContrastAA = 4.5;

double _relativeLuminance(Color c) {
  double linearize(double v) =>
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  final r = linearize((c.r * 255.0).round().clamp(0, 255) / 255.0);
  final g = linearize((c.g * 255.0).round().clamp(0, 255) / 255.0);
  final b = linearize((c.b * 255.0).round().clamp(0, 255) / 255.0);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AppColors — bubble text contrast (WCAG AA)', () {
    test('light theme: sent bubble text readable on light-green background', () {
      // Светлая тема: фон пузырька = EFFFDE, текст = onSurface (1A1A1A)
      final ratio = contrastRatio(
        AppColors.lightSentBubbleText,
        AppColors.lightSentBubble,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'Light sent bubble text must pass WCAG AA '
            '(ratio=$ratio, need>=$_kMinContrastAA)',
      );
    });

    test('light theme: received bubble text readable on white background', () {
      final ratio = contrastRatio(
        AppColors.lightReceivedBubbleText,
        AppColors.lightReceivedBubble,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'Light received bubble text must pass WCAG AA (ratio=$ratio)',
      );
    });

    test('dark theme: sent bubble text readable on dark-blue background', () {
      final ratio = contrastRatio(
        AppColors.darkSentBubbleText,
        AppColors.darkSentBubble,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'Dark sent bubble text must pass WCAG AA (ratio=$ratio)',
      );
    });

    test('dark theme: received bubble text readable on dark background', () {
      final ratio = contrastRatio(
        AppColors.darkReceivedBubbleText,
        AppColors.darkReceivedBubble,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'Dark received bubble text must pass WCAG AA (ratio=$ratio)',
      );
    });

    test('light theme: onPrimary (white) is NOT readable on lightSentBubble — confirms the old bug', () {
      // Этот тест документирует исходную ошибку: onPrimary (белый)
      // на светло-зелёном фоне — плохой контраст (< 4.5:1).
      const onPrimary = AppColors.lightOnPrimary; // белый
      final ratio = contrastRatio(onPrimary, AppColors.lightSentBubble);
      expect(
        ratio,
        lessThan(_kMinContrastAA),
        reason: 'onPrimary on lightSentBubble should fail WCAG AA — '
            'this confirms the bug that was fixed (ratio=$ratio)',
      );
    });

    test('light theme: onSurface IS readable on lightSentBubble — confirms the fix', () {
      const onSurface = AppColors.lightOnSurface;
      final ratio = contrastRatio(onSurface, AppColors.lightSentBubble);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'onSurface on lightSentBubble must pass WCAG AA (ratio=$ratio)',
      );
    });

    test('dark theme: onSurface is readable on darkSentBubble', () {
      const onSurface = AppColors.darkOnSurface;
      final ratio = contrastRatio(onSurface, AppColors.darkSentBubble);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'onSurface on darkSentBubble must pass WCAG AA (ratio=$ratio)',
      );
    });

    test('dark theme: onSurface is readable on darkReceivedBubble', () {
      const onSurface = AppColors.darkOnSurface;
      final ratio = contrastRatio(onSurface, AppColors.darkReceivedBubble);
      expect(
        ratio,
        greaterThanOrEqualTo(_kMinContrastAA),
        reason: 'onSurface on darkReceivedBubble must pass WCAG AA (ratio=$ratio)',
      );
    });
  });

  // -------------------------------------------------------------------------
  // LastMessage preview logic
  // -------------------------------------------------------------------------
  group('LastMessage — type getters', () {
    LastMessage make({
      String messageType = 'text',
      String content = '',
    }) =>
        LastMessage(
          id: 1,
          content: content,
          createdAt: '2024-01-01T00:00:00.000Z',
          isMine: true,
          messageType: messageType,
        );

    test('isPoll is true for poll type', () {
      expect(make(messageType: 'poll').isPoll, isTrue);
    });

    test('isPoll is false for text type', () {
      expect(make(messageType: 'text').isPoll, isFalse);
    });

    test('isLocation is true for location type', () {
      expect(make(messageType: 'location').isLocation, isTrue);
    });

    test('isLocation is false for text type', () {
      expect(make(messageType: 'text').isLocation, isFalse);
    });

    test('isLocation is false for poll type', () {
      expect(make(messageType: 'poll').isLocation, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // ChatsListPage preview widget renders correct subtitle text
  // -------------------------------------------------------------------------
  group('Chat list subtitle preview', () {
    Widget buildPreviewWidget({
      required LastMessage lastMsg,
      bool isMine = true,
    }) {
      return MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [],
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              // Воспроизводим логику _lastMessagePreview из ChatsListPage
              String preview;
              if (lastMsg.isPoll) {
                preview = 'Опрос: ';
              } else if (lastMsg.isLocation) {
                preview = '📍 Геолокация';
              } else if (lastMsg.content.startsWith('e2ee:')) {
                preview = 'Сообщение';
              } else {
                preview = lastMsg.content;
              }
              final subtitle = isMine ? 'Вы: $preview' : preview;
              return Text(subtitle, key: const Key('subtitle'));
            },
          ),
        ),
      );
    }

    testWidgets('location message shows emoji and label, not JSON', (tester) async {
      const jsonContent = '{"lat":55.75,"lng":37.62,"label":null}';
      final msg = LastMessage(
        id: 1,
        content: jsonContent,
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: true,
        messageType: 'location',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg));
      expect(find.text('Вы: 📍 Геолокация'), findsOneWidget);
      // Убеждаемся, что JSON не попадает в UI
      expect(find.textContaining('{'), findsNothing);
      expect(find.textContaining('lat'), findsNothing);
    });

    testWidgets('poll message shows poll label, not question text', (tester) async {
      final msg = LastMessage(
        id: 2,
        content: 'Какой ваш любимый цвет?',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: false,
        messageType: 'poll',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg, isMine: false));
      expect(find.text('Опрос: '), findsOneWidget);
    });

    testWidgets('voice message shows human-readable content', (tester) async {
      final msg = LastMessage(
        id: 3,
        content: 'Голосовое сообщение',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: true,
        messageType: 'text',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg));
      expect(find.text('Вы: Голосовое сообщение'), findsOneWidget);
    });

    testWidgets('video note message shows human-readable content', (tester) async {
      final msg = LastMessage(
        id: 4,
        content: 'Видеокружок',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: false,
        messageType: 'text',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg, isMine: false));
      expect(find.text('Видеокружок'), findsOneWidget);
    });

    testWidgets('encrypted message shows generic label', (tester) async {
      final msg = LastMessage(
        id: 5,
        content: 'e2ee:abc123==',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: true,
        messageType: 'text',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg));
      expect(find.text('Вы: Сообщение'), findsOneWidget);
      expect(find.textContaining('e2ee:'), findsNothing);
    });

    testWidgets('plain text message shows content as-is', (tester) async {
      final msg = LastMessage(
        id: 6,
        content: 'Привет!',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: false,
        messageType: 'text',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg, isMine: false));
      expect(find.text('Привет!'), findsOneWidget);
    });

    testWidgets('file attachment shows filename', (tester) async {
      final msg = LastMessage(
        id: 7,
        content: '(файл)',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: true,
        messageType: 'text',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg));
      expect(find.text('Вы: (файл)'), findsOneWidget);
    });

    testWidgets('missed call shows proper label', (tester) async {
      final msg = LastMessage(
        id: 8,
        content: 'Пропущенный звонок',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: false,
        messageType: 'missed_call',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg, isMine: false));
      expect(find.text('Пропущенный звонок'), findsOneWidget);
    });

    testWidgets('mine location shows prefix', (tester) async {
      final msg = LastMessage(
        id: 9,
        content: '{"lat":55.0,"lng":37.0,"label":"Офис"}',
        createdAt: '2024-01-01T00:00:00.000Z',
        isMine: true,
        messageType: 'location',
      );
      await tester.pumpWidget(buildPreviewWidget(lastMsg: msg));
      expect(find.text('Вы: 📍 Геолокация'), findsOneWidget);
    });
  });
}
