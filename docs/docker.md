# Docker Deployment

## Быстрый старт

### Использование docker-compose

1. Скопируйте `.env.example` в `.env` и настройте переменные окружения:
```bash
cp server/.env.example .env
```

2. Запустите контейнер:
```bash
docker-compose up -d
```

3. Проверьте статус:
```bash
docker-compose ps
```

4. Просмотрите логи:
```bash
docker-compose logs -f messenger-server
```

### Использование Docker напрямую

1. Соберите образ:
```bash
docker build -t messenger-server .
```

2. Запустите контейнер:
```bash
docker run -d \
  --name messenger-server \
  -p 3000:3000 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/uploads:/app/server/uploads \
  -v $(pwd)/public:/app/server/public \
  -e JWT_SECRET=your-secret-key \
  -e APP_BASE_URL=https://your-domain.com \
  messenger-server
```

## Переменные окружения

См. `server/.env.example` для полного списка переменных окружения.

## Volumes

- `./data` - база данных SQLite
- `./uploads` - загруженные файлы
- `./public` - статические файлы (web client)

## Health Checks

Контейнер автоматически проверяет здоровье через `/health` endpoint каждые 30 секунд.

## Обновление

1. Остановите контейнер:
```bash
docker-compose down
```

2. Обновите код и пересоберите:
```bash
git pull
docker-compose build
```

3. Запустите снова:
```bash
docker-compose up -d
```

## Бэкапы

Бэкапы базы данных находятся в `./data`. Рекомендуется регулярно копировать эту директорию.

## Production рекомендации

- Используйте внешнюю базу данных (PostgreSQL) вместо SQLite для продакшена
- Настройте reverse proxy (nginx) перед контейнером
- Используйте SSL/TLS сертификаты
- Настройте мониторинг и логирование
- Используйте secrets management для чувствительных данных
