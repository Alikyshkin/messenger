import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import 'api.dart';

/// OAuth-сервис для веба: Google через google_sign_in_web, VK/Telegram — заглушки.
class OAuthServiceImpl {
  static final Api _api = Api('');
  static String get _baseUrl => apiBaseUrl;

  static Future<OAuthProviders> getProviders() async {
    try {
      return await _api.getOAuthProviders();
    } catch (_) {
      return OAuthProviders(google: false, googleClientId: null, vk: false, telegram: false, phone: false);
    }
  }

  static Future<AuthResponse?> signInWithGoogle() async {
    final providers = await getProviders();
    if (!providers.google || providers.googleClientId == null || providers.googleClientId!.isEmpty) {
      throw UnimplementedError('Вход через Google не настроен');
    }
    final signIn = GoogleSignIn(clientId: providers.googleClientId);
    final account = await signIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) return null;
    return await _api.loginWithGoogle(idToken);
  }

  static Future<AuthResponse?> signInWithVk() async {
    throw UnimplementedError('Вход через VK на вебе не поддерживается');
  }

  static Future<void> signInWithTelegram() async {
    throw UnimplementedError('Вход через Telegram: встройте виджет на $_baseUrl/telegram-login');
  }

  static Future<void> sendPhoneCode(String phone) async {
    await _api.sendPhoneCode(phone);
  }

  static Future<AuthResponse> verifyPhoneCode(String phone, String code) async {
    return await _api.verifyPhoneCode(phone, code);
  }
}
