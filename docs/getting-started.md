# Быстрый старт

Руководство по быстрой установке и запуску мессенджера.

## Требования

- **Node.js** 20.x или выше
- **Flutter** 3.38.9 или выше
- **Git**


## Установка

### 1. Клонирование репозитория

```bash
git clone https://github.com/yourusername/messenger.git
cd messenger
```

### 2. Настройка сервера

```bash
cd server
cp .env.example .env
# Отредактируйте .env: задайте JWT_SECRET (см. раздел «Безопасность»)
npm install
npm start
```

Сервер будет доступен на `http://localhost:3000`. Данные хранятся в файле `server/messenger.db`.

### 3. Настройка клиента

```bash
cd client
flutter pub get
flutter run
```

Выберите устройство: **Chrome** (веб), Android, iOS, Windows, macOS.

**Важно:** для эмулятора Android замените в `client/lib/config.dart` адрес на `http://10.0.2.2:3000`. Для реального телефона укажите IP вашего компьютера в локальной сети.

## Первый запуск

1. Запустите сервер (см. выше)
2. Запустите клиент: `cd client && flutter run`
3. Зарегистрируйте нового пользователя
4. Начните общение!

## Сборка для продакшена

### Web

```bash
cd client
flutter build web
```

Результат в `client/build/web/` — можно положить на любой статический хостинг.

### Android

```bash
cd client
flutter build apk
```

APK файл будет в `client/build/app/outputs/flutter-apk/app-release.apk`.

### Windows

```bash
cd client
flutter build windows
```

Собранное приложение будет в `client/build/windows/runner/Release/`.

### macOS

```bash
cd client
flutter build macos
```

Приложение будет в `client/build/macos/Build/Products/Release/`.

## Следующие шаги

- [Настройка секретов](setup-secrets.md) — для автоматического деплоя
- [Развёртывание на сервере](deployment.md) — для продакшена
- [Руководство разработчика](development.md) — для разработки
