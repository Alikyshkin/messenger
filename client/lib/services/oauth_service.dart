// Условный импорт: на вебе — заглушка (без google_sign_in, flutter_login_vk),
// на мобильных/десктопе — полная реализация.
import 'package:flutter/widgets.dart';
import 'api.dart' show AuthResponse, OAuthProviders;
import 'oauth_service_web.dart'
    if (dart.library.io) 'oauth_service_io.dart'
    as oauth_impl;

/// Сервис для OAuth-входа (Google, VK, Telegram, телефон).
/// На вебе Google/VK SDK недоступны; на мобильных используется полная реализация.
class OAuthService {
  static Future<OAuthProviders> getProviders() =>
      oauth_impl.OAuthServiceImpl.getProviders();
  static Future<AuthResponse?> signInWithGoogle() =>
      oauth_impl.OAuthServiceImpl.signInWithGoogle();
  static Future<AuthResponse?> signInWithVk() =>
      oauth_impl.OAuthServiceImpl.signInWithVk();
  static Future<void> signInWithTelegram() =>
      oauth_impl.OAuthServiceImpl.signInWithTelegram();
  static Future<void> sendPhoneCode(String phone) =>
      oauth_impl.OAuthServiceImpl.sendPhoneCode(phone);
  static Future<AuthResponse> verifyPhoneCode(String phone, String code) =>
      oauth_impl.OAuthServiceImpl.verifyPhoneCode(phone, code);

  /// На вебе: виджет кнопки Google (renderButton). На IO — null.
  static Widget? getGoogleSignInButton() =>
      oauth_impl.OAuthServiceImpl.getGoogleSignInButton();

  /// На вебе: поток успешных авторизаций через Google. На IO — пустой поток.
  static Stream<AuthResponse?> get googleAuthStream =>
      oauth_impl.OAuthServiceImpl.googleAuthStream;
}
