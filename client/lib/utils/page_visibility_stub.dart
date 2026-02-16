/// Заглушка для не-web: вкладка считается видимой, уведомления не показываются.
bool get isPageVisible => true;

void setTabTitle(String title) {}

void resetTabTitle() {}

Future<bool> requestNotificationPermission() async => false;

Future<void> showPageNotification({
  required String title,
  required String body,
}) async {}

Future<void> focusWindow() async {}
