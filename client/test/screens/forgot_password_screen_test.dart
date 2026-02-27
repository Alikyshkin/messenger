import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/screens/forgot_password_screen.dart';
import '../helpers/widget_helpers.dart';

void main() {
  setUpAll(() async {
    await initTestPreferences();
  });

  group('ForgotPasswordScreen', () {
    testWidgets('renders logo, title and email form', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Мессенджер'), findsOneWidget);
      expect(find.text('Восстановление пароля'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('has links to login and register', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Вернуться ко входу'), findsOneWidget);
      expect(find.text('Нет аккаунта? Зарегистрироваться'), findsOneWidget);
    });

    testWidgets('shows error when email is empty', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Введите email'), findsOneWidget);
    });

    testWidgets('has no AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('has logo icon', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('send button text is Отправить ссылку', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Отправить ссылку'), findsOneWidget);
    });
  });
}
