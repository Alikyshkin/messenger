import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart';

import '../config.dart';
import 'api.dart';

/// OAuth-сервис для веба: Google через google_sign_in_web (renderButton + authenticationEvents).
class OAuthServiceImpl {
  static final Api _api = Api('');
  static String get _baseUrl => apiBaseUrl;

  static String? _clientId;
  static bool _initialized = false;
  static final StreamController<AuthResponse?> _authController =
      StreamController<AuthResponse?>.broadcast();
  static StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  static Future<OAuthProviders> getProviders() async {
    try {
      final p = await _api.getOAuthProviders();
      if (p.google && p.googleClientId != null && p.googleClientId!.isNotEmpty) {
        _clientId = p.googleClientId;
      }
      return p;
    } catch (_) {
      return OAuthProviders(
          google: false, googleClientId: null, vk: false, telegram: false, phone: false);
    }
  }

  /// Инициализация Google Sign-In для веба (вызывать перед показом кнопки).
  static Future<void> _ensureGoogleInit() async {
    if (_initialized || _clientId == null) return;
    _clientId ??= (await getProviders()).googleClientId;
    if (_clientId == null || _clientId!.isEmpty) return;

    final signIn = GoogleSignIn.instance;
    await signIn.initialize(clientId: _clientId);
    _initialized = true;

    _authSub?.cancel();
    _authSub = signIn.authenticationEvents.listen((event) async {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final user = event.user;
        final idToken = user.authentication.idToken;
        if (idToken != null) {
          try {
            final res = await _api.loginWithGoogle(idToken);
            _authController.add(res);
          } catch (_) {
            _authController.add(null);
          }
        }
      }
    });
  }

  /// Поток успешных авторизаций через Google (для веба).
  static Stream<AuthResponse?> get googleAuthStream => _authController.stream;

  /// Виджет кнопки Google для веба (renderButton). Null если Google не настроен.
  static Widget? getGoogleSignInButton() {
    if (!kIsWeb) return null;
    if (_clientId == null) return null;
    return _GoogleSignInWebButton();
  }

  /// На вебе authenticate() не поддерживается — используется renderButton.
  static Future<AuthResponse?> signInWithGoogle() async {
    if (!kIsWeb) return null;
    await _ensureGoogleInit();
    // На вебе кнопка уже показана; результат приходит через googleAuthStream.
    return null;
  }

  static Future<AuthResponse?> signInWithVk() async {
    throw UnimplementedError('Вход через VK на вебе не поддерживается');
  }

  static Future<void> signInWithTelegram() async {
    throw UnimplementedError(
        'Вход через Telegram: встройте виджет на $_baseUrl/telegram-login');
  }

  static Future<void> sendPhoneCode(String phone) async {
    await _api.sendPhoneCode(phone);
  }

  static Future<AuthResponse> verifyPhoneCode(String phone, String code) async {
    return await _api.verifyPhoneCode(phone, code);
  }
}

class _GoogleSignInWebButton extends StatefulWidget {
  @override
  State<_GoogleSignInWebButton> createState() => _GoogleSignInWebButtonState();
}

class _GoogleSignInWebButtonState extends State<_GoogleSignInWebButton> {
  @override
  void initState() {
    super.initState();
    OAuthServiceImpl._ensureGoogleInit();
  }

  @override
  Widget build(BuildContext context) {
    return renderButton(
      configuration: GSIButtonConfiguration(
        size: GSIButtonSize.medium,
        theme: GSIButtonTheme.filledBlue,
        text: GSIButtonText.signinWith,
      ),
    );
  }
}
