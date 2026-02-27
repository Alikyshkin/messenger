# Эксплуатация и обслуживание

## Мониторинг

Prometheus + Grafana: установить локально, настроить scrape target на `localhost:3000`. Prometheus: :9090, Grafana: :3001 (admin/admin). Метрики сервера: `/metrics` (HTTP, WebSocket, DB, сообщения, пользователи). Пароль Grafana в продакшене сменить.

## Бэкапы

- **Cron:** `0 2 * * * /path/to/scripts/backup-db.sh /path/to/messenger.db /path/to/backups`
- **Вручную:** `node scripts/backup-db.js server/messenger.db backups`
- Восстановление: распаковать `.gz`, скопировать в `server/messenger.db`. Хранить бэкапы отдельно/в облаке, периодически проверять восстановление.

## Кэширование (Redis)

В `.env`: `REDIS_URL=redis://localhost:6379`. Кэш: профили, контакты, чаты (TTL 30–60 мин). Без Redis приложение работает без кэша. Продакшен: пароль в URL, maxmemory, при необходимости Sentinel.

## Политика хранения данных

Переменные: `MESSAGE_RETENTION_DAYS=365`, `AUDIT_LOG_RETENTION_DAYS=90`, `RESET_TOKEN_RETENTION_DAYS=7`, `READ_RECEIPT_RETENTION_DAYS=180`. Очистка: `npm run cleanup`. Рекомендуется cron раз в день (например 3:00). Удаление необратимо; перед очисткой — бэкап.

## Логирование

Сервер: Pino (error, warn, info, debug). Просмотр: PM2 — `pm2 logs messenger`. Не логировать пароли и токены; при необходимости — ротация и отправка в ELK/Loki.
