import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/user_action_logger.dart';
import '../database/local_db.dart';
import '../models/user.dart';
import 'api.dart' show Api, ApiException, AuthResponse;
import 'e2ee_service.dart';

class AuthService extends ChangeNotifier {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'auth_user_id';
  static const _keyUsername = 'auth_username';
  static const _keyDisplayName = 'auth_display_name';

  User? _user;
  String _token = '';
  bool _loaded = false;

  User? get user => _user;
  String get token => _token;
  bool get isLoggedIn => _token.isNotEmpty;
  bool get loaded => _loaded;

  Future<void> load() async {
    final scope = logActionStart('auth_service', 'load', {'loaded': _loaded});
    if (_loaded) {
      scope.end({'result': 'already_loaded'});
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_keyToken) ?? '';
    if (_token.isNotEmpty) {
      final id = prefs.getInt(_keyUserId);
      final username = prefs.getString(_keyUsername);
      final displayName = prefs.getString(_keyDisplayName);
      if (id != null && username != null) {
        _user = User(
          id: id,
          username: username,
          displayName: displayName ?? username,
        );
      }
      try {
        final u = await Api(_token).me();
        _user = u;
        await prefs.setInt(_keyUserId, u.id);
        await prefs.setString(_keyUsername, u.username);
        await prefs.setString(_keyDisplayName, u.displayName);
        await _ensureE2EEKeys();
        scope.end({'result': 'ok', 'userId': u.id});
      } catch (e) {
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
          scope.end({'result': 'token_invalid', 'statusCode': e.statusCode});
          await clear();
        } else {
          scope.fail(e);
        }
      }
    } else {
      scope.end({'result': 'no_token'});
    }
    _loaded = true;
    notifyListeners();
  }

  bool _isRefreshing = false;

  Future<void> refreshUser() async {
    if (_token.isEmpty || _isRefreshing) {
      return;
    }
    _isRefreshing = true;
    try {
      final u = await Api(_token).me();
      _user = u;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyUserId, u.id);
      await prefs.setString(_keyUsername, u.username);
      await prefs.setString(_keyDisplayName, u.displayName);
      notifyListeners();
    } catch (_) {}
    _isRefreshing = false;
  }

  Future<void> _save(User u, String t) async {
    _user = u;
    _token = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, t);
    await prefs.setInt(_keyUserId, u.id);
    await prefs.setString(_keyUsername, u.username);
    await prefs.setString(_keyDisplayName, u.displayName);
    notifyListeners();
  }

  Future<void> clear() async {
    logAction('auth_service', 'clear', 'START', null, 'выход из аккаунта');
    _user = null;
    _token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyDisplayName);
    logAction('auth_service', 'clear', 'END', null, 'ok');
    notifyListeners();
  }

  Future<void> _ensureE2EEKeys() async {
    if (_token.isEmpty) {
      return;
    }
    try {
      final e2ee = E2EEService();
      final publicKey = await e2ee.ensureKeyPair();
      await Api(_token).patchMe(publicKey: publicKey);
      final u = await Api(_token).me();
      _user = u;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> login(String username, String password) async {
    logUserAction('auth_login', {'username': username});
    final api = Api('');
    final res = await api.login(username, password);
    await _save(res.user, res.token);
    await _ensureE2EEKeys();
    logUserAction('auth_login_ok', {'userId': res.user.id});
  }

  Future<void> loginWithOAuth(AuthResponse res) async {
    logUserAction('auth_login_oauth', {'userId': res.user.id});
    await _save(res.user, res.token);
    await _ensureE2EEKeys();
  }

  Future<void> register(
    String username,
    String password, [
    String? displayName,
    String? email,
  ]) async {
    logUserAction('auth_register', {'username': username});
    final api = Api('');
    await api.register(username, password, displayName, email);
    final res = await api.login(username, password);
    await _save(res.user, res.token);
    await _ensureE2EEKeys();
    logUserAction('auth_register_ok', {'userId': res.user.id});
  }

  Future<void> logout() async {
    await LocalDb.clearAll();
    await clear();
  }
}
