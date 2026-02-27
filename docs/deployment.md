# Развёртывание сервера

## VPS с PM2

Node.js 20, `npm install -g pm2`. Клонировать репо в `/opt/messenger`, в `server/` создать `.env` (JWT_SECRET, PORT, APP_BASE_URL, MESSENGER_DB_PATH). Запуск: `pm2 start index.js --name messenger`, затем `pm2 save` и `pm2 startup`. Обновление: `git pull`, `npm ci --omit=dev`, `pm2 restart messenger`.

## HTTPS

Домен с A-записью на сервер. Установить nginx и certbot: `sudo apt install nginx certbot python3-certbot-nginx`. Конфиг nginx: proxy_pass на 127.0.0.1:3000, заголовки Upgrade/Connection для WebSocket. Включить сайт, затем `sudo certbot --nginx -d ваш-домен.com`. В приложении задать `APP_BASE_URL=https://ваш-домен.com` и перезапустить.

## Автодеплой

Секреты в GitHub: см. [setup-secrets.md](setup-secrets.md). При пуше в `main` код загружается на сервер по SSH и PM2 перезапускает сервер.

## Troubleshooting

- Сервер не стартует: `pm2 logs messenger`, проверить `.env` и порты.
- Сайт не открывается: проверить `pm2 status`, nginx (`nginx -t`, логи), firewall (порты 80, 443, 3000).
- Данные не сохраняются: проверить, что `MESSENGER_DB_PATH` указывает на постоянный путь и директория существует.
