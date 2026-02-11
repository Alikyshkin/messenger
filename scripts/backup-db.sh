#!/bin/bash

# Скрипт для автоматического бэкапа базы данных мессенджера
# Использование: ./backup-db.sh [путь_к_базе] [путь_к_бэкапам]

set -e

# Путь к базе данных (по умолчанию)
DB_PATH="${1:-server/messenger.db}"

# Директория для бэкапов (по умолчанию)
BACKUP_DIR="${2:-backups}"

# Создаём директорию для бэкапов, если её нет
mkdir -p "$BACKUP_DIR"

# Имя файла бэкапа с датой и временем
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/messenger_${TIMESTAMP}.db"

# Проверяем существование базы данных
if [ ! -f "$DB_PATH" ]; then
    echo "Ошибка: База данных не найдена: $DB_PATH"
    exit 1
fi

# Создаём бэкап используя SQLite backup
sqlite3 "$DB_PATH" ".backup '$BACKUP_FILE'"

# Сжимаем бэкап для экономии места
gzip -f "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

echo "Бэкап создан: $BACKUP_FILE"

# Удаляем старые бэкапы (старше 30 дней)
find "$BACKUP_DIR" -name "messenger_*.db.gz" -mtime +30 -delete

echo "Старые бэкапы (старше 30 дней) удалены"

# Выводим список последних бэкапов
echo ""
echo "Последние бэкапы:"
ls -lh "$BACKUP_DIR"/messenger_*.db.gz 2>/dev/null | tail -5 || echo "Бэкапы не найдены"
