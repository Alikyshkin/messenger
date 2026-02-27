import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/screens/register_screen.dart';
import '../helpers/widget_helpers.dart';

void main() {
  setUpAll(() async {
    await initTestPreferences();
  });

  group('RegisterScreen', () {
    testWidgets('renders logo, title and registration form', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Мессенджер'), findsOneWidget);
      expect(find.text('Регистрация'), findsOneWidget);
      // 5 fields: username, displayName, email, password, repeat password
      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('has link to login screen', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Уже есть аккаунт? Войти'), findsOneWidget);
    });

    testWidgets('shows error when passwords do not match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
      await tester.enterText(find.byType(TextFormField).at(3), 'password123');
      await tester.enterText(find.byType(TextFormField).at(4), 'different456');

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Пароли не совпадают'), findsOneWidget);
    });

    testWidgets('shows error when password too short', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
      await tester.enterText(find.byType(TextFormField).at(3), 'abc');
      await tester.enterText(find.byType(TextFormField).at(4), 'abc');

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Минимум 6 символов'), findsOneWidget);
    });

    testWidgets('shows error when username too short', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'ab');
      await tester.enterText(find.byType(TextFormField).at(3), 'password123');
      await tester.enterText(find.byType(TextFormField).at(4), 'password123');

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Минимум 3 символа'), findsOneWidget);
    });

    testWidgets('no mismatch error shown when passwords match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
      await tester.enterText(find.byType(TextFormField).at(3), 'password123');
      await tester.enterText(find.byType(TextFormField).at(4), 'password123');

      // Trigger validation without calling _submit by tapping and pumping once
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();

      expect(find.text('Пароли не совпадают'), findsNothing);
    });

    testWidgets('has no AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('has logo icon', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithApp(child: const RegisterScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });
}
