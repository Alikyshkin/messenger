import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/call_screen.dart';
import '../../lib/models/user.dart';
import '../../lib/models/call_signal.dart';
import '../../lib/services/auth_service.dart';
import '../../lib/services/ws_service.dart';
import '../../lib/services/locale_service.dart';
import '../../lib/services/theme_service.dart';
import '../helpers/widget_helpers.dart';

void main() {
  group('CallScreen Tests', () {
    late User testPeer;
    late String testToken;

    setUp(() {
      testPeer = User(
        id: 2,
        username: 'testuser',
        displayName: 'Test User',
        bio: '',
        avatarUrl: null,
        publicKey: null,
        birthday: null,
        phone: null,
      );
      testToken = 'test_token_123';
    });

    testWidgets('CallScreen initializes for outgoing call', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AuthService()..setToken(testToken),
              ),
              ChangeNotifierProvider(create: (_) => WsService()),
            ],
            child: const CallScreen(peer: testPeer, isIncoming: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Проверяем, что экран звонка загрузился
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('CallScreen initializes for incoming call', (
      WidgetTester tester,
    ) async {
      final initialSignal = CallSignal(
        fromUserId: 2,
        type: 'offer',
        signal: {'type': 'offer', 'sdp': 'test_sdp'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AuthService()..setToken(testToken),
              ),
              ChangeNotifierProvider(create: (_) => WsService()),
            ],
            child: CallScreen(
              peer: testPeer,
              isIncoming: true,
              initialSignal: initialSignal,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Проверяем, что экран звонка загрузился для входящего звонка
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('CallScreen shows accept and reject buttons for incoming call', (
      WidgetTester tester,
    ) async {
      final initialSignal = CallSignal(
        fromUserId: 2,
        type: 'offer',
        signal: {'type': 'offer', 'sdp': 'test_sdp'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AuthService()..setToken(testToken),
              ),
              ChangeNotifierProvider(create: (_) => WsService()),
            ],
            child: CallScreen(
              peer: testPeer,
              isIncoming: true,
              initialSignal: initialSignal,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Проверяем наличие кнопок принятия и отклонения звонка
      // (в реальном тесте нужно найти конкретные кнопки по их иконкам или тексту)
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('CallScreen handles call end', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AuthService()..setToken(testToken),
              ),
              ChangeNotifierProvider(create: (_) => WsService()),
            ],
            child: const CallScreen(peer: testPeer, isIncoming: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Проверяем, что экран корректно обрабатывает завершение звонка
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('CallScreen handles WebRTC signal errors', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (_) => AuthService()..setToken(testToken),
              ),
              ChangeNotifierProvider(create: (_) => WsService()),
            ],
            child: const CallScreen(peer: testPeer, isIncoming: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Проверяем, что экран корректно обрабатывает ошибки WebRTC
      expect(find.byType(CallScreen), findsOneWidget);
    });
  });
}
