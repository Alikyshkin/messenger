import 'package:flutter/foundation.dart';

/// Сервис для принудительного обновления списка чатов.
/// Вызывается при возврате на главный экран и при восстановлении приложения из фона.
class ChatListRefreshService extends ChangeNotifier {
  /// Запросить обновление списка чатов (например, при возврате на главный экран).
  void requestRefresh() {
    notifyListeners();
  }
}
