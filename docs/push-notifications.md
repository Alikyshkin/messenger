# Push-уведомления с Firebase Cloud Messaging

Проект поддерживает push-уведомления через Firebase Cloud Messaging (FCM) для Android, iOS и Web.

## Настройка

### 1. Создание Firebase проекта

1. Перейдите на [Firebase Console](https://console.firebase.google.com/)
2. Создайте новый проект или выберите существующий
3. Добавьте приложения для Android, iOS и/или Web
4. Скачайте файл конфигурации для каждого приложения

### 2. Получение Service Account

1. В Firebase Console перейдите в **Project Settings** → **Service Accounts**
2. Нажмите **Generate New Private Key**
3. Сохраните JSON файл с credentials

### 3. Настройка сервера

Добавьте в `.env` один из вариантов:

**Вариант 1: Путь к файлу**
```env
FCM_SERVICE_ACCOUNT_PATH=/path/to/firebase-service-account.json
```

**Вариант 2: JSON в переменной окружения**
```env
FCM_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...","private_key":"..."}
```

## API Endpoints

### Регистрация FCM токена

```http
POST /push/register
Authorization: Bearer <token>
Content-Type: application/json

{
  "fcm_token": "device-fcm-token",
  "device_id": "optional-device-id",
  "device_name": "iPhone 12",
  "platform": "ios"
}
```

### Удаление FCM токена

```http
POST /push/unregister
Authorization: Bearer <token>
Content-Type: application/json

{
  "fcm_token": "device-fcm-token"
}
```

### Тестовое уведомление

```http
POST /push/test
Authorization: Bearer <token>
```

## Интеграция в клиентском приложении

### Flutter (пример)

```dart
import 'package:firebase_messaging/firebase_messaging.dart';

// Получить FCM токен
final fcmToken = await FirebaseMessaging.instance.getToken();

// Зарегистрировать токен на сервере
await http.post(
  Uri.parse('$apiBaseUrl/push/register'),
  headers: {
    'Authorization': 'Bearer $authToken',
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'fcm_token': fcmToken,
    'device_id': deviceId,
    'device_name': deviceName,
    'platform': Platform.isAndroid ? 'android' : 'ios',
  }),
);

// Обработка уведомлений
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  // Уведомление получено когда приложение открыто
  print('Got a message: ${message.notification?.title}');
});

FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
```

### Web (пример)

```javascript
import { getMessaging, getToken } from 'firebase/messaging';

const messaging = getMessaging();
const token = await getToken(messaging, {
  vapidKey: 'your-vapid-key'
});

// Зарегистрировать токен
await fetch('/push/register', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    fcm_token: token,
    platform: 'web',
  }),
});
```

## Автоматические уведомления

Сервер автоматически отправляет push-уведомления при:

1. **Новом личном сообщении** - получателю сообщения
2. **Новом групповом сообщении** - всем участникам группы (кроме отправителя)

## Типы уведомлений

### Новое сообщение

```json
{
  "notification": {
    "title": "Имя отправителя",
    "body": "Текст сообщения"
  },
  "data": {
    "type": "new_message",
    "message_id": "123",
    "sender_id": "456",
    "sender_name": "Имя отправителя",
    "content": "Текст сообщения",
    "chat_type": "personal"
  }
}
```

### Новое групповое сообщение

```json
{
  "notification": {
    "title": "Название группы",
    "body": "Имя отправителя: Текст сообщения"
  },
  "data": {
    "type": "new_group_message",
    "message_id": "123",
    "group_id": "789",
    "sender_id": "456",
    "sender_name": "Имя отправителя",
    "content": "Текст сообщения",
    "chat_type": "group"
  }
}
```

## Обработка невалидных токенов

Сервер автоматически определяет невалидные токены при отправке. Клиентское приложение должно:

1. Обрабатывать ошибки регистрации токена
2. Обновлять токен при его изменении
3. Удалять токен при выходе из аккаунта

## Troubleshooting

### Уведомления не приходят

1. Проверьте настройки Firebase проекта
2. Убедитесь, что Service Account настроен правильно
3. Проверьте логи сервера на наличие ошибок FCM
4. Убедитесь, что токен зарегистрирован в БД

### Токен не регистрируется

1. Проверьте формат токена
2. Убедитесь, что пользователь авторизован
3. Проверьте логи сервера

### Ошибки отправки

- `messaging/invalid-registration-token` - токен недействителен, нужно удалить
- `messaging/registration-token-not-registered` - токен не зарегистрирован
- `messaging/message-rate-exceeded` - превышен лимит отправки

## Production рекомендации

1. **Безопасность**:
   - Храните Service Account JSON в безопасном месте
   - Не коммитьте credentials в репозиторий
   - Используйте secrets management (AWS Secrets Manager, HashiCorp Vault)

2. **Производительность**:
   - Используйте multicast для отправки нескольким устройствам
   - Кэшируйте токены пользователей
   - Обрабатывайте ошибки асинхронно

3. **Мониторинг**:
   - Отслеживайте успешность отправки уведомлений
   - Мониторьте количество невалидных токенов
   - Логируйте все ошибки FCM

4. **UX**:
   - Позвольте пользователям отключать уведомления
   - Настройте звуки и вибрацию
   - Используйте badge для счетчика непрочитанных сообщений
