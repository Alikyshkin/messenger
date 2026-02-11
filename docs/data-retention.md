# Политика хранения данных

Приложение автоматически удаляет старые данные согласно политике хранения для обеспечения приватности и соответствия GDPR.

## Политики хранения

### Сообщения
- **Срок хранения**: 365 дней (1 год) по умолчанию
- **Настройка**: `MESSAGE_RETENTION_DAYS`
- **Что удаляется**: Старые личные и групповые сообщения, включая вложения

### Audit Logs
- **Срок хранения**: 90 дней по умолчанию
- **Настройка**: `AUDIT_LOG_RETENTION_DAYS`
- **Что удаляется**: Старые записи audit logs

### Токены сброса пароля
- **Срок хранения**: 7 дней (автоматически после истечения)
- **Настройка**: `RESET_TOKEN_RETENTION_DAYS`
- **Что удаляется**: Истёкшие токены сброса пароля

### Read Receipts
- **Срок хранения**: 180 дней по умолчанию
- **Настройка**: `READ_RECEIPT_RETENTION_DAYS`
- **Что удаляется**: Старые метки прочитанных сообщений

## Запуск очистки

### Вручную

```bash
npm run cleanup
```

### Автоматически (Cron)

Добавьте в crontab:

```bash
# Очистка данных каждый день в 3:00
0 3 * * * cd /path/to/messenger/server && npm run cleanup
```

### Через systemd timer

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

## Настройка через переменные окружения

Добавьте в `.env`:

```env
# Политики хранения данных (в днях)
MESSAGE_RETENTION_DAYS=365
AUDIT_LOG_RETENTION_DAYS=90
RESET_TOKEN_RETENTION_DAYS=7
READ_RECEIPT_RETENTION_DAYS=180
```

## Что происходит при очистке

1. **Сообщения**:
   - Удаляются сообщения старше установленного срока
   - Удаляются связанные файлы вложений с диска
   - Удаляются реакции и опросы связанные с сообщениями
   - Обновляются FTS индексы

2. **Audit Logs**:
   - Удаляются записи старше установленного срока
   - Сохраняется только необходимая информация для compliance

3. **Токены**:
   - Удаляются истёкшие токены сброса пароля
   - Освобождается место в БД

4. **Read Receipts**:
   - Очищаются старые метки прочитанных сообщений
   - Сохраняется только актуальная информация

## Мониторинг

Проверьте логи для отслеживания процесса очистки:

```bash
# Просмотр логов очистки
grep "Data retention cleanup" /var/log/messenger.log
```

## Важные замечания

1. **Бэкапы**: Убедитесь, что у вас есть бэкапы перед запуском очистки
2. **Необратимость**: Удаление данных необратимо
3. **Производительность**: Очистка может занять время на больших объёмах данных
4. **Лучшее время**: Запускайте очистку в нерабочее время

## Соответствие GDPR

Автоматическая очистка данных помогает:
- Минимизировать хранение персональных данных
- Соответствовать принципу "минимизации данных"
- Снижать риск утечки данных
- Упрощать управление данными
