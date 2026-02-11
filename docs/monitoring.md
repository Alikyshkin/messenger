# Мониторинг с Prometheus и Grafana

Проект использует Prometheus для сбора метрик и Grafana для визуализации.

## Метрики

Сервер экспортирует метрики в формате Prometheus на endpoint `/metrics`:

### HTTP метрики
- `http_requests_total` - общее количество HTTP запросов
- `http_request_duration_seconds` - длительность HTTP запросов
- `http_request_size_bytes` - размер HTTP запросов
- `http_response_size_bytes` - размер HTTP ответов

### WebSocket метрики
- `websocket_connections_total` - количество активных WebSocket подключений
- `websocket_messages_total` - общее количество WebSocket сообщений

### Database метрики
- `database_queries_total` - общее количество запросов к БД
- `database_query_duration_seconds` - длительность запросов к БД

### Бизнес метрики
- `messages_total` - общее количество отправленных сообщений
- `users_total` - общее количество зарегистрированных пользователей
- `active_users` - количество активных (онлайн) пользователей

## Запуск мониторинга

### Использование docker-compose

```bash
# Запуск сервера и мониторинга
docker-compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Или только мониторинг (если сервер уже запущен)
docker-compose -f docker-compose.monitoring.yml up -d
```

### Доступ к сервисам

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001
  - Username: `admin`
  - Password: `admin` (измените в продакшене!)

## Настройка Prometheus

Конфигурация Prometheus находится в `monitoring/prometheus.yml`.

По умолчанию Prometheus собирает метрики с:
- `messenger-server:3000/metrics` - метрики приложения
- `localhost:9090` - собственные метрики Prometheus

## Настройка Grafana

### Datasource

Prometheus datasource настраивается автоматически через `monitoring/grafana/datasources/prometheus.yml`.

### Dashboards

Базовый dashboard находится в `monitoring/grafana/dashboards/dashboard.json`.

Для создания собственных дашбордов:
1. Откройте Grafana UI
2. Перейдите в `Dashboards` → `New Dashboard`
3. Создайте панели с метриками из Prometheus
4. Экспортируйте dashboard в JSON
5. Сохраните в `monitoring/grafana/dashboards/`

## Полезные запросы PromQL

### Топ-5 самых медленных endpoints
```promql
topk(5, histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])))
```

### Ошибки HTTP (4xx и 5xx)
```promql
sum(rate(http_requests_total{status_code=~"4..|5.."}[5m])) by (status_code)
```

### Средняя длительность запросов по endpoint
```promql
avg(rate(http_request_duration_seconds_sum[5m])) by (route)
```

### Количество активных пользователей
```promql
active_users
```

### Скорость отправки сообщений
```promql
rate(messages_total[5m])
```

## Production рекомендации

1. **Безопасность**:
   - Измените пароль Grafana по умолчанию
   - Используйте HTTPS для доступа к Grafana и Prometheus
   - Ограничьте доступ к `/metrics` endpoint (только для Prometheus)

2. **Хранение данных**:
   - Настройте retention policy в Prometheus
   - Используйте внешнее хранилище для долгосрочного хранения метрик (например, Thanos)

3. **Алерты**:
   - Настройте Alertmanager для уведомлений
   - Создайте алерты на критические метрики (высокая ошибка, медленные запросы)

4. **Производительность**:
   - Настройте scrape interval в зависимости от нагрузки
   - Используйте recording rules для сложных запросов

## Интеграция с другими инструментами

### Alertmanager

Добавьте в `prometheus.yml`:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

### Node Exporter

Для мониторинга системных метрик сервера добавьте Node Exporter в `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

## Troubleshooting

### Метрики не собираются

1. Проверьте доступность endpoint `/metrics`:
```bash
curl http://localhost:3000/metrics
```

2. Проверьте логи Prometheus:
```bash
docker logs prometheus
```

3. Проверьте конфигурацию в Prometheus UI: Status → Targets

### Grafana не показывает данные

1. Проверьте datasource в Grafana: Configuration → Data Sources
2. Убедитесь, что Prometheus доступен из контейнера Grafana
3. Проверьте логи Grafana:
```bash
docker logs grafana
```
