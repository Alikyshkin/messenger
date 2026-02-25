import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_login_vk/flutter_login_vk.dart';
import 'api.dart';

/// OAuth-сервис для мобильных и десктопа (Android, iOS, macOS, Windows, Linux).
class OAuthServiceImpl {
  static final Api _api = Api('');

  static Future<OAuthProviders> getProviders() async {
    try {
      return await _api.getOAuthProviders();
    } catch (_) {
      return OAuthProviders(
        google: false,
        googleClientId: null,
        vk: false,
        telegram: false,
        phone: false,
      );
    }
  }

  static Future<AuthResponse?> signInWithGoogle() async {
    try {
      final signIn = GoogleSignIn.instance;
      await signIn.initialize();
      if (!signIn.supportsAuthenticate()) return null;

      final account = await signIn.authenticate(
        scopeHint: ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) return null;

      return await _api.loginWithGoogle(idToken);
    } catch (e) {
      rethrow;
    }
  }

  static Future<AuthResponse?> signInWithVk() async {
    try {
      final vkLogin = VKLogin();
      final initResult = await vkLogin.initSdk(
        scope: [VKScope.email, VKScope.friends],
      );
      if (initResult.isError) throw initResult.asError!.error;

      final result = await vkLogin.logIn(
        scope: [VKScope.email, VKScope.friends],
      );
      if (result.isError) throw result.asError!.error;

      final loginResult = result.asValue!.value;
      if (loginResult.isCanceled || loginResult.accessToken == null) {
        return null;
      }

      return await _api.loginWithVk(
        loginResult.accessToken!.token,
        loginResult.accessToken!.userId,
      );
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> signInWithTelegram() async {
    throw UnimplementedError(
      'Вход через Telegram: откройте страницу с виджетом',
    );
  }

  static Future<void> sendPhoneCode(String phone) async {
    await _api.sendPhoneCode(phone);
  }

  static Future<AuthResponse> verifyPhoneCode(String phone, String code) async {
    return await _api.verifyPhoneCode(phone, code);
  }

  static Widget? getGoogleSignInButton() => null;
  static Stream<AuthResponse?> get googleAuthStream => const Stream.empty();
}
