import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyLocale = 'locale';

class LocaleService extends ChangeNotifier {
  Locale? _locale;
  bool _loaded = false;

  Locale? get locale => _locale;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLocale);
    if (code == 'en') {
      _locale = const Locale('en');
    } else if (code == 'ru') {
      _locale = const Locale('ru');
    } else {
      _locale = null; // default: system or we use ru
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    if (_locale?.languageCode == value.languageCode) {
      return;
    }
    _locale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, value.languageCode);
    notifyListeners();
  }
}
