import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/contacts_screen.dart';
import '../screens/start_chat_screen.dart';
import '../screens/create_group_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/group_profile_screen.dart';
import '../screens/media_gallery_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/register_screen.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/ws_call_listener.dart';
import '../widgets/minimized_call_overlay.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../services/api.dart';

/// Конфигурация роутов приложения с поддержкой URL для веб
GoRouter createAppRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = authService;
      final isLoggedIn = auth.isLoggedIn;
      final isLoggingIn = state.matchedLocation == '/login' || 
                          state.matchedLocation == '/register' ||
                          state.matchedLocation == '/forgot-password';
      
      // Если пользователь не авторизован и пытается зайти на защищенные страницы
      if (!isLoggedIn && !isLoggingIn) {
        return '/login';
      }
      
      // Если пользователь авторизован и пытается зайти на страницы входа
      if (isLoggedIn && isLoggingIn) {
        return '/';
      }
      
      return null; // Разрешаем навигацию
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final auth = Provider.of<AuthService>(context, listen: false);
          if (!auth.loaded) {
            return const _AppLoadingScreen();
          }
          return auth.isLoggedIn
              ? MinimizedCallOverlay(
                  child: const WsCallListener(child: HomeScreen()),
                )
              : const LoginScreen();
        },
        routes: [
          GoRoute(
            path: 'chat/:peerId',
            builder: (context, state) {
              final peerIdStr = state.pathParameters['peerId']!;
              final peerId = int.tryParse(peerIdStr);
              if (peerId == null) {
                return const Scaffold(
                  body: Center(child: Text('Неверный ID пользователя')),
                );
              }
              // Загружаем пользователя из API
              final auth = Provider.of<AuthService>(context, listen: false);
              final api = Api(auth.token);
              return FutureBuilder<User>(
                future: api.getUserProfile(peerId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Scaffold(
                      body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Пользователь не найден"}')),
                    );
                  }
                  return ChatScreen(peer: snapshot.data!);
                },
              );
            },
          ),
          GoRoute(
            path: 'group/:groupId',
            builder: (context, state) {
              final groupIdStr = state.pathParameters['groupId']!;
              final groupId = int.tryParse(groupIdStr);
              if (groupId == null) {
                return const Scaffold(
                  body: Center(child: Text('Неверный ID группы')),
                );
              }
              // Загружаем группу из API
              final auth = Provider.of<AuthService>(context, listen: false);
              final api = Api(auth.token);
              return FutureBuilder<Group>(
                future: api.getGroup(groupId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Scaffold(
                      body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Группа не найдена"}')),
                    );
                  }
                  return GroupChatScreen(group: snapshot.data!);
                },
              );
            },
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: 'contacts',
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: 'start-chat',
            builder: (context, state) => const StartChatScreen(),
          ),
          GoRoute(
            path: 'create-group',
            builder: (context, state) => const CreateGroupScreen(),
          ),
          GoRoute(
            path: 'user/:userId',
            builder: (context, state) {
              final userIdStr = state.pathParameters['userId']!;
              final userId = int.tryParse(userIdStr);
              if (userId == null) {
                return const Scaffold(
                  body: Center(child: Text('Неверный ID пользователя')),
                );
              }
              final auth = Provider.of<AuthService>(context, listen: false);
              final api = Api(auth.token);
              return FutureBuilder<User>(
                future: api.getUserProfile(userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Scaffold(
                      body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Пользователь не найден"}')),
                    );
                  }
                  return UserProfileScreen(user: snapshot.data!);
                },
              );
            },
          ),
          GoRoute(
            path: 'group-profile/:groupId',
            builder: (context, state) {
              final groupIdStr = state.pathParameters['groupId']!;
              final groupId = int.tryParse(groupIdStr);
              if (groupId == null) {
                return const Scaffold(
                  body: Center(child: Text('Неверный ID группы')),
                );
              }
              final auth = Provider.of<AuthService>(context, listen: false);
              final api = Api(auth.token);
              return FutureBuilder<Group>(
                future: api.getGroup(groupId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Scaffold(
                      body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Группа не найдена"}')),
                    );
                  }
                  return GroupProfileScreen(group: snapshot.data!);
                },
              );
            },
          ),
          GoRoute(
            path: 'media/:peerId',
            builder: (context, state) {
              final peerIdStr = state.pathParameters['peerId']!;
              final peerId = int.tryParse(peerIdStr);
              if (peerId == null) {
                return const Scaffold(
                  body: Center(child: Text('Неверный ID')),
                );
              }
              final isGroup = state.uri.queryParameters['group'] == 'true';
              // Загружаем пользователя или группу из API
              final auth = Provider.of<AuthService>(context, listen: false);
              final api = Api(auth.token);
              if (isGroup) {
                return FutureBuilder<Group>(
                  future: api.getGroup(peerId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Scaffold(
                        body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Группа не найдена"}')),
                      );
                    }
                    return MediaGalleryScreen(group: snapshot.data!);
                  },
                );
              } else {
                return FutureBuilder<User>(
                  future: api.getUserProfile(peerId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Scaffold(
                        body: Center(child: Text('Ошибка загрузки: ${snapshot.error ?? "Пользователь не найден"}')),
                      );
                    }
                    return MediaGalleryScreen(peer: snapshot.data!);
                  },
                );
              }
            },
          ),
        ],
      ),
    ],
  );
}

/// Красивый экран загрузки вместо белого — в одном стиле с загрузкой в index.html.
class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final surface = theme.scaffoldBackgroundColor;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    surface,
                    theme.colorScheme.surfaceContainerHighest,
                  ]
                : [
                    const Color(0xFFF5F5F5),
                    const Color(0xFFE0E0E0),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary,
                      primary.withValues(alpha: 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 44,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Мессенджер',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
