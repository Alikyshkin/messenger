import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/screens/login_screen.dart';
import '../helpers/widget_helpers.dart';

void main() {
  setUpAll(() async {
    await initTestPreferences();
  });

  group('LoginScreen', () {
    testWidgets('renders title and login form', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Мессенджер'), findsOneWidget);
      expect(find.text('Войти'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('has links to forgot password and register', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(child: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Забыли пароль?'), findsOneWidget);
      expect(find.text('Нет аккаунта? Зарегистрироваться'), findsOneWidget);
    });
  });
}
