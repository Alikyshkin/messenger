# Развёртывание сервера

## Docker (рекомендуется)

1. Установить Docker и Docker Compose. На сервере: `docker login`.
2. Создать `/opt/messenger`, положить `docker-compose.yml`:

```yaml
services:
  messenger-server:
    image: ${DOCKER_USERNAME}/messenger-server:latest
    container_name: messenger-server
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - JWT_SECRET=ваш_секрет
      - MESSENGER_DB_PATH=/app/data/messenger.db
      - APP_BASE_URL=https://ваш-домен.com
      - CORS_ORIGINS=https://ваш-домен.com
    volumes:
      - ./data:/app/data
      - ./uploads:/app/server/uploads
      - ./public:/app/server/public
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
networks:
  default:
```

Заменить `JWT_SECRET` (например `openssl rand -base64 32`), `APP_BASE_URL`, `CORS_ORIGINS`. Создать `mkdir -p data uploads public`.

3. Запуск: `docker compose pull && docker compose up -d`. Проверка: `curl http://localhost:3000/health`.
4. Обновление: `docker compose pull && docker compose up -d`.

## VPS с PM2

Node.js 20, `npm install -g pm2`. Клонировать репо в `/opt/messenger`, в `server/` создать `.env` (JWT_SECRET, PORT, APP_BASE_URL, MESSENGER_DB_PATH). Запуск: `pm2 start index.js --name messenger`, затем `pm2 save` и `pm2 startup`. Обновление: `git pull`, `npm ci --omit=dev`, `pm2 restart messenger`.

## HTTPS

Домен с A-записью на сервер. Установить nginx и certbot: `sudo apt install nginx certbot python3-certbot-nginx`. Конфиг nginx: proxy_pass на 127.0.0.1:3000, заголовки Upgrade/Connection для WebSocket. Включить сайт, затем `sudo certbot --nginx -d ваш-домен.com`. В приложении задать `APP_BASE_URL=https://ваш-домен.com` и перезапустить.

## Автодеплой

Секреты в GitHub: см. [setup-secrets.md](setup-secrets.md). При пуше в `main` образ собирается, пушится в Docker Hub, на сервере выполняется обновление контейнера по SSH.

## Миграция с PM2 на Docker

Остановить PM2: `pm2 stop messenger && pm2 delete messenger && pm2 save`. Развернуть Docker по шагам выше, использовать те же пути к data/uploads при необходимости.

## Troubleshooting

- Контейнер не стартует: `docker compose logs messenger-server`, проверить env и порты.
- "pull access denied": на сервере выполнить `docker login`.
- Сайт не открывается: проверить `pm2 status` / `docker compose ps`, nginx (`nginx -t`, логи), firewall (порты 80, 443, 3000).
- Данные не сохраняются: проверить, что `MESSENGER_DB_PATH` указывает на постоянный volume/путь и директория существует.
