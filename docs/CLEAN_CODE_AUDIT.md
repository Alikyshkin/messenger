# Аудит проекта по критериям Clean Code

Отчёт составлен на основе критериев Clean Code (SOLID, DRY, KISS — Robert C. Martin, Codacy) и анализа кодовой базы messenger (server + client).

---

## 1. Критерии Clean Code (использованы при анализе)

- **SOLID**: единственная ответственность, открытость/закрытость, подстановка Лисков, разделение интерфейсов, зависимость от абстракций.
- **DRY (Don't Repeat Yourself)**: устранение дублирования.
- **KISS (Keep It Simple)**: простые, понятные решения.
- **Читаемость**: осмысленные имена, короткие функции, минимум магии.
- **Тестируемость**: покрытие тестами и предсказуемость кода.

---

## 2. Ошибки и неработающий код

| Что | Где | Что сделать |
|-----|-----|-------------|
| **Неопределённая переменная `register`** | `server/index.js`, эндпоинт `/metrics` | **Исправлено:** добавлен импорт `metricsRegister` (default export из `utils/metrics.js`) и использование `metricsRegister.contentType`; тело ответа передаётся через переменную `body`, чтобы не затенять импортированный объект `metrics`. |
| **Jest-тесты не запускаются из npm test** | `server/package.json`: скрипт `test` вызывает только `node --test tests/...` | В `test` не входят файлы из `__tests__/`. Либо добавить запуск Jest (`jest` или `node --experimental-vm-modules node_modules/jest/bin/jest.js`), либо перевести тесты на Node.js Test Runner и перенести в `tests/`. |
| **Некорректный импорт app в Jest-тестах** | `server/__tests__/auth.test.js`, `__tests__/messages.test.js`: `const module = await import('../index.js'); app = module.default` | `index.js` экспортирует `{ app, server }`, а не `export default`. Нужно: `app = module.app; server = module.server`. |

---

## 3. Лишнее и сомнительное

| Что | Где | Рекомендация |
|-----|-----|--------------|
| **Заголовки CORS `X-Foo`, `X-Bar`** | `server/index.js`, строка 123: `exposedHeaders: ['Content-Length', 'X-Foo', 'X-Bar']` | Похоже на заглушки. Удалить `X-Foo` и `X-Bar` или заменить на реальные заголовки, если они нужны клиенту. |
| **Импорт middleware без использования** | `server/index.js`: импортируются `metricsMiddleware` и `auditMiddleware`, но ни один не передаётся в `app.use()` | Либо подключить: например, `app.use(metricsMiddleware)` до маршрутов, `app.use(auditMiddleware)` там, где нужен аудит. Либо убрать неиспользуемые импорты. |
| **API versioning не используется маршрутами** | Маршруты подключены как `/auth`, `/contacts`, `/messages` и т.д., без префикса `/api/v1` | В `apiVersioning.js` проверяется путь вида `/api/v1/...`, текущие пути так не строятся. Либо ввести реальное версионирование (префикс `/api/v1`), либо упростить/удалить middleware, если версионирование не планируется. |
| **Линтер не настроен** | `server/package.json`: `"lint": "echo '⚠️ Lint не настроен...'"` | Подключить ESLint (и при необходимости Prettier), добавить скрипты `lint` и `lint:fix`, запускать в CI. |
| **Дублирование npm-скриптов Playwright** | `test:playwright` и `test:playwright:e2e` делают одно и то же (оба используют `playwright.e2e.config.js`) | Оставить один скрипт для E2E (например, `test:playwright:e2e`) и один для API (`test:playwright:api`), лишний удалить или явно развести по конфигам/назначению. |

---

## 4. Дублирование (DRY)

| Дубликат | Где | Рекомендация |
|----------|-----|--------------|
| **Проверка БД `SELECT 1`** | `server/index.js`: в обработчиках `/health` и `/ready` повторяется `db.prepare('SELECT 1').get()` и обработка ошибок | Вынести в общую функцию, например `checkDatabase(db)`, возвращающую `{ ok, error? }`, и использовать в обоих эндпоинтах. |
| **Хелперы auth/unique в Playwright** | `server/tests/playwright/messenger.spec.js` и `messenger.e2e.spec.js`: свои `unique()`, `PASSWORD`, логика регистрации/логина | Вынести в общий модуль, например `tests/playwright/helpers.js`: `unique()`, `PASSWORD`, `auth(request)`, при необходимости общие селекторы/ожидания для E2E. |
| **Получение display_name пользователя** | В нескольких местах: `server/index.js` (WebSocket), `server/routes/groups.js` и др.: `db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(id)` и `user?.display_name \|\| user?.username \|\| 'User'` | Вынести в утилиту, например `getUserDisplayName(db, userId)` в `server/utils/users.js` (или рядом с другими хелперами БД) и использовать везде. |
| **Паттерн «контакты пользователя»** | `server/index.js` (ws on connection и on close): `db.prepare('SELECT contact_id FROM contacts WHERE user_id = ?').all(userId).map(r => r.contact_id)` | Вынести в функцию, например `getContactIds(db, userId)`, и вызывать в обоих местах. |
| **Логика удаления пользователя (каскад)** | Похожая последовательность удалений по таблицам в `server/scripts/delete-users-except.js` и в `server/routes/users.js` (delete account) | Вынести общую логику каскадного удаления в один модуль (например, `server/utils/userDeletion.js`) и вызывать из скрипта и из роута. |

---

## 5. Недотестированное

| Что | Где | Рекомендация |
|-----|-----|-------------|
| **Интеграционный тест не входит в test** | `server/tests/messages-integration.test.js` не указан в скрипте `test` в `package.json` | Добавить в `test` или отдельный скрипт `test:integration` и вызывать при CI. |
| **Роуты без тестов** | Роуты: `export`, `gdpr`, `media`, `sync`, `version`, `polls`, `push`, `oauth`, `groups` (частично) | Добавить интеграционные или e2e-тесты для критичных сценариев (хотя бы smoke: регистрация, логин, основные запросы). |
| **Утилиты без юнит-тестов** | `server/utils/`: `sanitizeLogs.js`, `dataRetention.js`, `queryOptimizer.js`, `accountLockout.js`, `blocked.js`, `privacy.js`, `cipher.js` | Покрыть юнит-тестами чистые функции (санитизация, проверки блокировок, политики приватности). |
| **Middleware без тестов** | `middleware/`: `validation.js`, `sanitize.js`, `fileValidation.js`, `pagination.js`, `apiVersioning.js`, `csrf.js` | Добавить тесты на валидацию, санитизацию и поведение middleware на граничных входных данных. |
| **Jest-тесты в __tests__** | `__tests__/auth.test.js`, `messages.test.js`, `validation.test.js` используют свою БД (test.db) и не запускаются через `npm test` | Либо включить Jest в основной пайплайн и починить импорт app/server, либо перенести сценарии в `tests/` на Node.js Test Runner и единую тестовую БД (:memory:). |

---

## 6. Что можно убрать или упростить

| Что | Где | Рекомендация |
|-----|-----|-------------|
| **Лишние артефакты Playwright** | `server/test-results/` с `error-context.md` и артефактами прогонов | Добавить `test-results/` и при необходимости `playwright-report/`, `blob-report/` в `.gitignore` и не коммитить. |
| **Два набора тестов (Jest и Node test)** | `server/__tests__/` (Jest + supertest) и `server/tests/` (node:test) | Унифицировать: один test runner (предпочтительно Node.js Test Runner) и одна структура папок; миграция Jest-тестов в `tests/` и удаление `jest.config.js` и папки `__tests__` после переноса. |
| **Сложная логика trust proxy** | `server/index.js`, строки 57–72: несколько веток по `TRUST_PROXY` и окружению | Упростить до: если `TRUST_PROXY === 'true'` — trust proxy 1, иначе не использовать, без автоматического определения по DOCKER/KUBERNETES, либо вынести в config. |
| **Inline HTML для сброса пароля** | `server/index.js`, строки 348–402: большая HTML-строка в коде | Вынести в шаблон (например, `server/templates/reset-password.html`) или отдельный модуль, подключать через `readFileSync` или шаблонизатор. |
| **Пустой catch в WebSocket** | `server/index.js`, строка 451: `} catch (_) {}` | Минимум: логировать ошибку (`log.warn`/`log.error`). При необходимости — обрабатывать по типу ошибки и закрывать соединение при критичных сбоях. |

---

## 7. Структура и единообразие

| Вопрос | Рекомендация |
|--------|--------------|
| **Именование папок тестов** | ✅ Введена единая схема: `tests/unit/`, `tests/integration/`, `tests/e2e/`, `tests/playwright/` (UI), `tests/smoke/`. |
| **Константы** | Часть настроек захардкожена (например, порты в Playwright). Вынести в `config/constants.js` или переменные окружения (PLAYWRIGHT_TEST_PORT и т.д.) и использовать везде оттуда. |
| **Логика в index.js** | Много логики WebSocket и health в одном файле. Вынести обработчики WebSocket-сообщений в отдельный модуль (например, `server/wsHandlers.js`), health/ready — в `server/health.js` или оставить в index, но короткими вызовами к утилитам. |

---

## 8. Клиент (Flutter)

| Что | Где | Рекомендация |
|-----|-----|-------------|
| **TODO в коде** | `client/windows/flutter/CMakeLists.txt`, `client/android/app/build.gradle.kts`: комментарии TODO | Либо выполнить (указать applicationId, signing config), либо оформить как задачи в трекере и сослаться в комментарии. |
| **Именование константы** | `client/lib/styles/app_sizes.dart`: `iconXXXL` | Заменить на осмысленное имя без «XXX», например `iconSizeExtraLarge` или `iconSize48`. |

---

## 9. Приоритеты действий

1. **Критично**: исправить использование `register` в `server/index.js` (метрики).
2. **Критично**: починить или удалить Jest-тесты в `__tests__` (импорт app/server и запуск).
3. **Высокий**: вынести дублирование проверки БД и контактов в index.js; общие хелперы Playwright.
4. **Высокий**: подключить или убрать `metricsMiddleware` и `auditMiddleware`; убрать `X-Foo`/`X-Bar` из CORS.
5. **Средний**: унифицировать тесты (один runner, одна структура); добавить в test `messages-integration.test.js`; покрыть ключевые утилиты и middleware.
6. **Низкий**: вынести HTML сброса пароля в шаблон; упростить trust proxy; добавить ESLint.

После изменений стоит прогнать полный набор тестов (`npm test`, Playwright API и E2E) и проверить health/ready и метрики вручную.
