# Задачи по аудиту Clean Code

Список оставшихся задач по результатам аудита (SOLID, DRY, KISS, читаемость, тестируемость). Выполненные пункты из отчёта удалены.

---

## Критично

- [x] **Jest-тесты не запускаются из npm test** — выполнено: тесты переведены на Node.js Test Runner и перенесены в `tests/`; скрипт `test` запускает `test:node` (node --test) для всех юнит-, интеграционных, e2e и smoke-тестов.
- [x] **Некорректный импорт app в Jest-тестах** — в `server/__tests__/auth.test.js`, `messages.test.js`: заменить `app = module.default` на `app = module.app; server = module.server`, т.к. `index.js` экспортирует `{ app, server }`, а не default.

---

## Высокий приоритет

- [x] **API versioning не используется** — маршруты без префикса `/api/v1`, а `apiVersioning.js` проверяет именно его. Либо ввести префикс `/api/v1` для маршрутов, либо упростить/удалить middleware.
- [x] **Дублирование npm-скриптов Playwright** — `test:playwright` и `test:playwright:e2e` делают одно и то же. Оставить один скрипт для E2E, лишний удалить или развести по конфигам.
- [x] **Проверка БД в /health и /ready** — вынести `db.prepare('SELECT 1').get()` и обработку ошибок в общую функцию `checkDatabase(db)` (например в `server/health.js`), возвращающую `{ ok, error? }`, и использовать в обоих эндпоинтах.
- [ ] **Паттерн «контакты пользователя»** — в `server/index.js` в двух местах (ws on connection и on close) повторяется `db.prepare('SELECT contact_id FROM contacts WHERE user_id = ?').all(userId).map(r => r.contact_id)`. Вынести в функцию `getContactIds(db, userId)` и вызывать в обоих местах.
- [ ] **Получение display_name пользователя** — во многих местах (index.js WebSocket, routes/groups.js, messages.js, export.js и др.) повторяется запрос `SELECT display_name, username FROM users WHERE id = ?` и `user?.display_name || user?.username || 'User'`. Вынести в утилиту `getUserDisplayName(db, userId)` (например в `server/utils/users.js`) и использовать везде.
- [x] **Хелперы auth/unique в Playwright** — в `server/tests/playwright/messenger.spec.js` и `messenger.e2e.spec.js` дублируются `unique()`, `PASSWORD`, логика регистрации/логина. Вынести в общий модуль `tests/playwright/helpers.js`: `unique()`, `PASSWORD`, `auth(request)`, при необходимости общие селекторы/ожидания.
- [x] **Логика удаления пользователя (каскад)** — похожая последовательность удалений по таблицам в `server/scripts/delete-users-except.js` и в `server/routes/users.js`. Вынести общую логику в модуль `server/utils/userDeletion.js` и вызывать из скрипта и из роута.

---

## Средний приоритет

- [x] **Интеграционный тест не входит в основной test** — `test:integration` есть отдельно, но в скрипт `test` в package.json не входит. Добавить вызов интеграционных тестов в `test` или явно запускать `test:integration` в CI.
- [ ] **Роуты без тестов** — роуты `export`, `gdpr`, `media`, `sync`, `version`, `polls`, `push`, `oauth`, `groups` (частично) без интеграционных/e2e-тестов. Добавить хотя бы smoke: регистрация, логин, основные запросы.
- [x] **Утилиты без юнит-тестов** — `server/utils/`: `sanitizeLogs.js`, `dataRetention.js`, `queryOptimizer.js`, `accountLockout.js`, `blocked.js`, `privacy.js`, `cipher.js`. Покрыть юнит-тестами чистые функции.
- [ ] **Middleware без тестов** — `validation.js`, `sanitize.js`, `fileValidation.js`, `pagination.js`, `apiVersioning.js`, `csrf.js`. Добавить тесты на граничных входных данных.
- [x] **Унификация тестов** — два набора: `__tests__/` (Jest + supertest) и `tests/` (node:test). Унифицировать: один test runner (предпочтительно Node.js Test Runner), одна структура папок; перенести сценарии из Jest в `tests/`, затем удалить `jest.config.js` и папку `__tests__`.
- [ ] **Константы** — порты в Playwright и др. захардкожены. Вынести в `config/constants.js` или переменные окружения (например `PLAYWRIGHT_TEST_PORT`) и использовать везде оттуда.
- [x] **Логика в index.js** — много логики WebSocket и health в одном файле. Вынести обработчики WebSocket-сообщений в отдельный модуль (например `server/wsHandlers.js`), health/ready — в `server/health.js` или короткие вызовы утилит.

---

## Низкий приоритет

- [x] **Пустой catch в WebSocket** — в `server/index.js` (около строки 627) `} catch (_) {}`. Минимум: логировать ошибку (`log.warn`/`log.error`); при необходимости обрабатывать по типу и закрывать соединение при критичных сбоях.
- [ ] **Артефакты Playwright** — при необходимости добавить `blob-report/` в `.gitignore` (уже есть `test-results/` и `playwright-report/`).
- [ ] **Клиент: TODO в коде** — `client/android/app/build.gradle.kts`: указать applicationId, signing config; `client/windows/flutter/CMakeLists.txt`: оформить как задачу в трекере или выполнить. Ссылаться в комментарии.
- [x] **Клиент: именование константы** — в `client/lib/styles/app_sizes.dart` заменить `iconXXXL` на осмысленное имя, например `iconSizeExtraLarge` или `iconSize48`.

---

## Критерии (для справки)

- **SOLID**: единственная ответственность, открытость/закрытость, подстановка Лисков, разделение интерфейсов, зависимость от абстракций.
- **DRY**: устранение дублирования.
- **KISS**: простые, понятные решения.
- **Читаемость**: осмысленные имена, короткие функции, минимум магии.
- **Тестируемость**: покрытие тестами и предсказуемость кода.

После изменений: прогнать полный набор тестов (`npm test`, `test:integration`, Playwright API и E2E), проверить health/ready и метрики вручную.
