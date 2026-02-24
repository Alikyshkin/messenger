# Руководство разработчика

## Окружение

- **Node.js** 20+, **Flutter** 3.38.9+, **Git**
- Сервер: `cd server && npm install`
- Клиент: `cd client && flutter pub get`
- Pre-commit: `./scripts/install-hooks.sh` (format, analyze, build web)

## Тестирование

- **Сервер:** `cd server && npm test` (unit + integration). Покрытие: `npm run test:coverage`. Watch: `npm run test:watch`.
- **Клиент:** `cd client && flutter test`. Покрытие: `flutter test --coverage`.
- **Структура:** `server/tests/unit/`, `server/tests/integration/`, `server/tests/playwright/` (E2E). Клиент: `client/test/`.
- **Стратегия:** unit — валидация, утилиты; API — auth, CRUD, чаты, сообщения; E2E — регистрация, логин, отправка сообщений.

## CI/CD

- **CI** (push/PR в main, develop): format, analyze, build web, `npm test`.
- **Deploy** (push в main): сборка образа → Docker Hub → деплой по SSH. Секреты: `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`.
- **Release** (тег `v*`): сборки под все платформы, GitHub Release. Версия в `client/pubspec.yaml` и `client/lib/config/version.dart`.

## Стандарты кода

- **Формат:** Dart — `dart format .`; JS — без Prettier.
- **Анализ:** `flutter analyze`; сервер — `npm run lint` (если есть).
- **Коммиты:** [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope):`, `fix(scope):`, `docs:`, `chore:` и т.д.
- **Именование:** Dart — PascalCase классы, camelCase функции; JS — PascalCase классы, camelCase, UPPER_SNAKE для констант.

## Версионирование

SemVer. Менять в `client/lib/config/version.dart` и `client/pubspec.yaml`. Релиз: тег `v1.0.0` → GitHub Actions создаёт релиз.

## Code Review

PR с проходом CI. Checklist: format, analyze, тесты, обновление доки при необходимости.
