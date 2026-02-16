import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_login_vk/flutter_login_vk.dart';
import '../config.dart';
import 'api.dart';

/// Сервис для OAuth-входа (Google, VK, Telegram, телефон).
/// Использует платформо-специфичные SDK.
class OAuthService {
  static final Api _api = Api('');
  static String get _baseUrl => apiBaseUrl;

  /// Получить список доступных провайдеров с сервера
  static Future<OAuthProviders> getProviders() async {
    try {
      return await _api.getOAuthProviders();
    } catch (_) {
      return OAuthProviders(google: false, vk: false, telegram: false, phone: false);
    }
  }

  /// Вход через Google
  static Future<AuthResponse?> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: null, // Для id_token нужен serverClientId в production
      );
      final account = await googleSignIn.signIn();
      if (account == null) return null;

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return null;

      return await _api.loginWithGoogle(idToken);
    } catch (e) {
      rethrow;
    }
  }

  /// Вход через VK
  static Future<AuthResponse?> signInWithVk() async {
    try {
      final vkLogin = VKLogin();
      final initResult = await vkLogin.initSdk(scope: [VKScope.email, VKScope.profile]);
      if (initResult.isError) throw initResult.asError!.error;

      final result = await vkLogin.logIn(scope: [VKScope.email, VKScope.profile]);
      if (result.isError) throw result.asError!.error;

      final loginResult = result.asValue!.value;
      if (loginResult.isCanceled || loginResult.accessToken == null) return null;

      return await _api.loginWithVk(
        loginResult.accessToken!.token,
        loginResult.accessToken!.userId,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Вход через Telegram (требует WebView с виджетом — на мобильных открывает URL)
  static Future<void> signInWithTelegram() async {
    // Telegram Login Widget работает через web. На мобильных можно открыть
    // страницу с виджетом. Для полной реализации нужен webview или deeplink.
    final url = '$_baseUrl/telegram-login';
    if (kIsWeb) {
      // На вебе — открыть в том же окне
      throw UnimplementedError('Telegram login на вебе: встройте виджет на страницу /telegram-login');
    }
    // На мобильных — открыть в браузере (пользователь вернётся по deeplink)
    throw UnimplementedError('Telegram login: откройте $_baseUrl/telegram-login в браузере');
  }

  /// Отправить SMS-код на телефон
  static Future<void> sendPhoneCode(String phone) async {
    await _api.sendPhoneCode(phone);
  }

  /// Верифицировать код и войти
  static Future<AuthResponse> verifyPhoneCode(String phone, String code) async {
    return await _api.verifyPhoneCode(phone, code);
  }
}
