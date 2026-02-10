import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/ws_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/ws_call_listener.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MessengerApp());
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..load()),
        ChangeNotifierProvider(create: (_) => WsService()),
      ],
      child: MaterialApp(
        title: 'Мессенджер',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF1A1A1A),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFE8E8E8),
            onPrimaryContainer: const Color(0xFF1A1A1A),
            secondary: const Color(0xFF6B6B6B),
            onSecondary: Colors.white,
            surface: Colors.white,
            onSurface: const Color(0xFF1A1A1A),
            surfaceContainerHighest: const Color(0xFFF0F0F0),
            onSurfaceVariant: const Color(0xFF6B6B6B),
            outline: const Color(0xFFE0E0E0),
            error: const Color(0xFF5C5C5C),
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF1A1A1A),
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 1.5),
            ),
            labelStyle: const TextStyle(color: Color(0xFF6B6B6B)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B6B6B),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A1A),
            ),
          ),
          dividerColor: const Color(0xFFE8E8E8),
          listTileTheme: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) {
            final auth = context.watch<AuthService>();
            if (!auth.loaded) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Загрузка...',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return auth.isLoggedIn
                ? const WsCallListener(child: HomeScreen())
                : const LoginScreen();
          },
          '/login': (context) => const LoginScreen(),
        },
      ),
    );
  }
}
