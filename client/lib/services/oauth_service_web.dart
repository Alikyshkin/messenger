import '../config.dart';
import 'api.dart';

/// OAuth-сервис для веба: Google/VK/Telegram SDK недоступны, используем заглушки.
class OAuthServiceImpl {
  static final Api _api = Api('');
  static String get _baseUrl => apiBaseUrl;

  static Future<OAuthProviders> getProviders() async {
    try {
      return await _api.getOAuthProviders();
    } catch (_) {
      return OAuthProviders(google: false, vk: false, telegram: false, phone: false);
    }
  }

  static Future<AuthResponse?> signInWithGoogle() async {
    // На вебе google_sign_in требует другую настройку; пока не поддерживаем
    throw UnimplementedError('Вход через Google на вебе пока не реализован');
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
