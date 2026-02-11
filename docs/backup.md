# Автоматические бэкапы базы данных

## Настройка автоматических бэкапов

### Вариант 1: Использование cron (Linux/macOS)

Добавьте в crontab для ежедневного бэкапа в 2:00 ночи:

```bash
crontab -e
```

Добавьте строку:
```
0 2 * * * /path/to/messenger/scripts/backup-db.sh /path/to/messenger/server/messenger.db /path/to/messenger/backups
```

### Вариант 2: Использование systemd timer (Linux)

Создайте файл `/etc/systemd/system/messenger-backup.service`:

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

Создайте файл `/etc/systemd/system/messenger-backup.timer`:

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

### Вариант 3: Использование Node.js скрипта

```bash
node scripts/backup-db.js server/messenger.db backups
```

## Восстановление из бэкапа

```bash
# Распаковка
gunzip backups/messenger_20240101_020000.db.gz

# Восстановление
sqlite3 server/messenger.db < backups/messenger_20240101_020000.db
# или
cp backups/messenger_20240101_020000.db server/messenger.db
```

## Рекомендации

- Храните бэкапы на отдельном диске или сервере
- Используйте облачное хранилище (S3, Google Cloud Storage) для критичных данных
- Тестируйте восстановление бэкапов периодически
- Настройте мониторинг успешности бэкапов
