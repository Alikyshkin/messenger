// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool get isPageVisible => !(html.document.hidden ?? false);

String? _originalTitle;

/// Меняет заголовок вкладки (видно в таб-баре браузера, даже когда вкладка не активна).
void setTabTitle(String title) {
  _originalTitle ??= html.document.title;
  html.document.title = title;
}

/// Восстанавливает исходный заголовок вкладки.
void resetTabTitle() {
  if (_originalTitle != null) {
    html.document.title = _originalTitle!;
    _originalTitle = null;
  }
}

Future<bool> requestNotificationPermission() async {
  if (html.Notification.permission == 'granted') {
    return true;
  }
  if (html.Notification.permission == 'denied') {
    return false;
  }
  try {
    final p = await html.Notification.requestPermission();
    return p == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> showPageNotification({
  required String title,
  required String body,
}) async {
  try {
    if (html.Notification.permission != 'granted') {
      return;
    }
    html.Notification(title, body: body);
  } catch (_) {}
}

Future<void> focusWindow() async {
  try {
    // Window.focus() removed from dart:html; call via JS interop at runtime
    (html.window as dynamic).focus();
  } catch (_) {}
}
