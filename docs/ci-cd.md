# CI/CD Pipeline

Проект использует GitHub Actions для автоматизации тестирования, сборки и развёртывания.

## Workflows

### CI (Continuous Integration)

Файл: `.github/workflows/ci.yml`

**Триггеры:**
- Push в ветки `main`, `develop`, `feature/**`
- Pull requests в `main` и `develop`

**Задачи:**
1. **Test** - Запуск тестов на Node.js 20.x
2. **Build** - Сборка Docker образа (без публикации)
3. **Security** - Проверка безопасности зависимостей

### Deploy

Файл: `.github/workflows/deploy.yml`

**Триггеры:**
- Push в ветку `main`
- Ручной запуск через `workflow_dispatch`

**Задачи:**
1. Сборка Docker образа
2. Публикация в Docker Hub
3. Развёртывание на сервер через SSH

**Требуемые Secrets:**
- `DOCKER_USERNAME` - имя пользователя Docker Hub
- `DOCKER_PASSWORD` - пароль или токен Docker Hub
- `DEPLOY_HOST` - адрес сервера для развёртывания
- `DEPLOY_USER` - пользователь для SSH подключения
- `DEPLOY_SSH_KEY` - приватный SSH ключ для подключения

### Release

Файл: `.github/workflows/release.yml`

**Триггеры:**
- Push тегов вида `v*` (например, `v1.0.0`)

**Задачи:**
1. Запуск тестов
2. Сборка Docker образа с версией из тега
3. Публикация в Docker Hub
4. Создание GitHub Release

## Настройка Secrets

В настройках репозитория GitHub (`Settings` → `Secrets and variables` → `Actions`) добавьте:

- `DOCKER_USERNAME` - ваш Docker Hub username
- `DOCKER_PASSWORD` - ваш Docker Hub password или access token
- `DEPLOY_HOST` - IP или домен вашего сервера
- `DEPLOY_USER` - пользователь для SSH (обычно `root` или `deploy`)
- `DEPLOY_SSH_KEY` - приватный SSH ключ для подключения к серверу

## Локальное тестирование

Для локального тестирования CI/CD можно использовать [act](https://github.com/nektos/act):

```bash
# Установка act
brew install act  # macOS
# или
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Запуск CI workflow локально
act -j test

# Запуск всех jobs
act
```

## Развёртывание

### Автоматическое развёртывание

При push в `main` ветку автоматически:
1. Собирается Docker образ
2. Публикация в Docker Hub
3. Подключение к серверу по SSH
4. Обновление контейнера через `docker-compose`

### Ручное развёртывание

1. Перейдите в `Actions` → `Deploy`
2. Нажмите `Run workflow`
3. Выберите ветку и запустите

### Развёртывание релиза

1. Создайте тег:
```bash
git tag v1.0.0
git push origin v1.0.0
```

2. GitHub Actions автоматически создаст релиз и опубликует образ

## Мониторинг

Проверьте статус workflows в разделе `Actions` репозитория GitHub.

## Troubleshooting

### Тесты не запускаются

Убедитесь, что:
- Существует директория `server/tests/` или файлы тестов
- В `package.json` есть скрипт `test`
- Тесты не требуют внешних зависимостей (используйте `:memory:` для БД)

### Docker build падает

Проверьте:
- Корректность `Dockerfile`
- Наличие всех необходимых файлов в контексте сборки
- `.dockerignore` не исключает необходимые файлы

### Развёртывание не работает

Проверьте:
- Правильность SSH ключа в secrets
- Доступность сервера по SSH
- Наличие `docker-compose.yml` на сервере
- Права доступа к директории проекта на сервере
