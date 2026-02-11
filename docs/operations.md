# Эксплуатация и обслуживание

Руководство по эксплуатации, мониторингу и обслуживанию сервера мессенджера.

## Содержание

- [Мониторинг](#мониторинг)
- [Бэкапы](#бэкапы)
- [Кэширование](#кэширование)
- [Политика хранения данных](#политика-хранения-данных)
- [Логирование](#логирование)

---

## Мониторинг

### Prometheus и Grafana

Проект использует Prometheus для сбора метрик и Grafana для визуализации.

#### Запуск мониторинга

```bash
docker-compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

**Доступ:**
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001
  - Username: `admin`
  - Password: `admin` (измените в продакшене!)

#### Метрики

Сервер экспортирует метрики на endpoint `/metrics`:

**HTTP метрики:**
- `http_requests_total` - общее количество HTTP запросов
- `http_request_duration_seconds` - длительность HTTP запросов
- `http_request_size_bytes` - размер HTTP запросов
- `http_response_size_bytes` - размер HTTP ответов

**WebSocket метрики:**
- `websocket_connections_total` - количество активных WebSocket подключений
- `websocket_messages_total` - общее количество WebSocket сообщений

**Database метрики:**
- `database_queries_total` - общее количество запросов к БД
- `database_query_duration_seconds` - длительность запросов к БД

**Бизнес метрики:**
- `messages_total` - общее количество отправленных сообщений
- `users_total` - общее количество зарегистрированных пользователей
- `active_users` - количество активных (онлайн) пользователей

#### Полезные запросы PromQL

**Топ-5 самых медленных endpoints:**
```promql
topk(5, histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])))
```

**Ошибки HTTP (4xx и 5xx):**
```promql
sum(rate(http_requests_total{status_code=~"4..|5.."}[5m])) by (status_code)
```

**Средняя длительность запросов по endpoint:**
```promql
avg(rate(http_request_duration_seconds_sum[5m])) by (route)
```

**Количество активных пользователей:**
```promql
active_users
```

**Скорость отправки сообщений:**
```promql
rate(messages_total[5m])
```

#### Production рекомендации

1. **Безопасность:**
   - Измените пароль Grafana по умолчанию
   - Используйте HTTPS для доступа к Grafana и Prometheus
   - Ограничьте доступ к `/metrics` endpoint (только для Prometheus)

2. **Хранение данных:**
   - Настройте retention policy в Prometheus
   - Используйте внешнее хранилище для долгосрочного хранения метрик (например, Thanos)

3. **Алерты:**
   - Настройте Alertmanager для уведомлений
   - Создайте алерты на критические метрики (высокая ошибка, медленные запросы)

---

## Бэкапы

### Автоматические бэкапы

#### Вариант 1: Cron (Linux/macOS)

Добавьте в crontab для ежедневного бэкапа в 2:00 ночи:

```bash
crontab -e
```

Добавьте строку:
```
0 2 * * * /path/to/messenger/scripts/backup-db.sh /path/to/messenger/server/messenger.db /path/to/messenger/backups
```

#### Вариант 2: systemd timer (Linux)

Создайте `/etc/systemd/system/messenger-backup.service`:

```ini
[Unit]
Description=Messenger Database Backup
After=network.target

[Service]
Type=oneshot
User=your-user
WorkingDirectory=/path/to/messenger
ExecStart=/path/to/messenger/scripts/backup-db.sh /path/to/messenger/server/messenger.db /path/to/messenger/backups
```

Создайте `/etc/systemd/system/messenger-backup.timer`:

```ini
[Unit]
Description=Run Messenger Backup Daily
Requires=messenger-backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Активируйте timer:
```bash
sudo systemctl enable messenger-backup.timer
sudo systemctl start messenger-backup.timer
```

#### Вариант 3: Node.js скрипт

```bash
node scripts/backup-db.js server/messenger.db backups
```

### Восстановление из бэкапа

```bash
# Распаковка
gunzip backups/messenger_20240101_020000.db.gz

# Восстановление
cp backups/messenger_20240101_020000.db server/messenger.db

# Или через SQLite
sqlite3 server/messenger.db < backups/messenger_20240101_020000.db
```

### Рекомендации

- Храните бэкапы на отдельном диске или сервере
- Используйте облачное хранилище (S3, Google Cloud Storage) для критичных данных
- Тестируйте восстановление бэкапов периодически
- Настройте мониторинг успешности бэкапов

---

## Кэширование

### Redis

Проект использует Redis для кэширования данных и улучшения производительности.

#### Настройка

Добавьте в `.env`:

```env
REDIS_URL=redis://localhost:6379
REDIS_SESSION_TTL=86400      # TTL для сессий (24 часа)
REDIS_USER_TTL=3600           # TTL для данных пользователей (1 час)
REDIS_CONTACTS_TTL=1800       # TTL для списка контактов (30 минут)
REDIS_CHATS_TTL=1800          # TTL для списка чатов (30 минут)
```

#### Запуск Redis

**Docker:**
```bash
docker run -d --name redis -p 6379:6379 redis:alpine
```

**Docker Compose:**
Добавьте в `docker-compose.yml`:

```yaml
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

volumes:
  redis-data:
```

#### Что кэшируется

- **Данные пользователей:** Профиль пользователя (`/users/me`, `/users/:id`), TTL: 1 час
- **Контакты:** Список контактов пользователя (`/contacts`), TTL: 30 минут
- **Чаты:** Список чатов пользователя (`/chats`), TTL: 30 минут

#### Fallback поведение

Если Redis недоступен или не настроен:
- Кэширование автоматически отключается
- Все запросы идут напрямую в базу данных
- Приложение продолжает работать без кэширования
- В логах появляются предупреждения

#### Инвалидация кэша

Кэш автоматически инвалидируется при:
- Обновлении профиля пользователя
- Добавлении/удалении контакта
- Изменении данных группы

#### Production рекомендации

1. **Безопасность:**
   - Используйте пароль для Redis: `REDIS_URL=redis://:password@host:6379`
   - Ограничьте доступ к Redis только из приложения
   - Используйте SSL/TLS для удалённых подключений

2. **Производительность:**
   - Настройте maxmemory и политику eviction
   - Используйте персистентность (RDB или AOF) для важных данных
   - Мониторьте использование памяти

3. **Высокая доступность:**
   - Используйте Redis Sentinel для отказоустойчивости
   - Или Redis Cluster для горизонтального масштабирования

---

## Политика хранения данных

Приложение автоматически удаляет старые данные согласно политике хранения для обеспечения приватности и соответствия GDPR.

### Политики хранения

| Тип данных | Срок хранения | Настройка |
|------------|---------------|-----------|
| **Сообщения** | 365 дней (1 год) | `MESSAGE_RETENTION_DAYS` |
| **Audit Logs** | 90 дней | `AUDIT_LOG_RETENTION_DAYS` |
| **Токены сброса пароля** | 7 дней | `RESET_TOKEN_RETENTION_DAYS` |
| **Read Receipts** | 180 дней | `READ_RECEIPT_RETENTION_DAYS` |

### Настройка через переменные окружения

Добавьте в `.env`:

```env
MESSAGE_RETENTION_DAYS=365
AUDIT_LOG_RETENTION_DAYS=90
RESET_TOKEN_RETENTION_DAYS=7
READ_RECEIPT_RETENTION_DAYS=180
```

### Запуск очистки

**Вручную:**
```bash
npm run cleanup
```

**Автоматически (Cron):**
```bash
# Очистка данных каждый день в 3:00
0 3 * * * cd /path/to/messenger/server && npm run cleanup
```

**Через systemd timer:**

Создайте `/etc/systemd/system/messenger-cleanup.service`:

```ini
[Unit]
Description=Messenger Data Cleanup
After=network.target

[Service]
Type=oneshot
User=messenger
WorkingDirectory=/opt/messenger/server
ExecStart=/usr/bin/npm run cleanup
Environment=NODE_ENV=production
Environment=MESSENGER_DB_PATH=/opt/messenger/data/messenger.db
```

И `/etc/systemd/system/messenger-cleanup.timer`:

```ini
[Unit]
Description=Run Messenger Data Cleanup Daily
Requires=messenger-cleanup.service

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
```

Активируйте:
```bash
sudo systemctl enable messenger-cleanup.timer
sudo systemctl start messenger-cleanup.timer
```

### Что происходит при очистке

1. **Сообщения:**
   - Удаляются сообщения старше установленного срока
   - Удаляются связанные файлы вложений с диска
   - Удаляются реакции и опросы связанные с сообщениями
   - Обновляются FTS индексы

2. **Audit Logs:**
   - Удаляются записи старше установленного срока
   - Сохраняется только необходимая информация для compliance

3. **Токены:**
   - Удаляются истёкшие токены сброса пароля
   - Освобождается место в БД

4. **Read Receipts:**
   - Очищаются старые метки прочитанных сообщений
   - Сохраняется только актуальная информация

### Важные замечания

1. **Бэкапы:** Убедитесь, что у вас есть бэкапы перед запуском очистки
2. **Необратимость:** Удаление данных необратимо
3. **Производительность:** Очистка может занять время на больших объёмах данных
4. **Лучшее время:** Запускайте очистку в нерабочее время

### Соответствие GDPR

Автоматическая очистка данных помогает:
- Минимизировать хранение персональных данных
- Соответствовать принципу "минимизации данных"
- Снижать риск утечки данных
- Упрощать управление данными

---

## Логирование

### Сервер

Сервер использует **Pino** для структурированного логирования.

**Уровни логов:**
- `error` - критические ошибки
- `warn` - предупреждения
- `info` - информационные сообщения
- `debug` - отладочная информация

**Просмотр логов:**

**PM2:**
```bash
pm2 logs messenger
```

**Docker:**
```bash
docker compose logs -f messenger-server
```

### Клиент

Клиент использует стандартное логирование Flutter (`print`, `debugPrint`).

**В продакшене:**
- Логи отключены для уменьшения размера бандла
- Используйте удалённое логирование для критичных ошибок

### Рекомендации

1. **Структурированные логи:** Используйте JSON формат для логов
2. **Ротация логов:** Настройте ротацию логов для предотвращения переполнения диска
3. **Мониторинг:** Интегрируйте логи с системами мониторинга (ELK, Loki)
4. **Конфиденциальность:** Не логируйте чувствительные данные (пароли, токены)
