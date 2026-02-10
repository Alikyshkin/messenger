// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool get isPageVisible => !html.document.hidden;

Future<bool> requestNotificationPermission() async {
  if (html.Notification.permission == 'granted') return true;
  if (html.Notification.permission == 'denied') return false;
  try {
    final p = await html.Notification.requestPermission();
    return p == 'granted';
  } catch (_) {
    return false;
  }
}

Future<void> showPageNotification({required String title, required String body}) async {
  try {
    if (html.Notification.permission != 'granted') return;
    html.Notification(title, body: body);
  } catch (_) {}
}

Future<void> focusWindow() async {
  try {
    html.window.focus();
  } catch (_) {}
}
