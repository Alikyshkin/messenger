# Настройка сервера для автоматического деплоя с Docker

После того как вы настроили секреты в GitHub, нужно выполнить **один раз** на сервере следующие шаги.

## Что нужно сделать на сервере

### 1. Подключитесь к серверу по SSH

```bash
ssh ваш_пользователь@ваш_сервер
```

### 2. Установите Docker и Docker Compose (если еще не установлены)

**Ubuntu/Debian:**

```bash
# Обновляем пакеты
sudo apt-get update

# Устанавливаем Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Добавляем текущего пользователя в группу docker (чтобы не использовать sudo)
sudo usermod -aG docker $USER

# Устанавливаем Docker Compose
sudo apt-get install -y docker-compose-plugin

# Выйдите и войдите снова, чтобы применились изменения группы
exit
```

**Проверьте установку:**

```bash
docker --version
docker compose version
```

### 3. Войдите в Docker Hub на сервере

Это нужно, чтобы сервер мог скачивать образы из Docker Hub:

```bash
docker login
# Введите ваш Docker Hub username и password (или access token)
```

**Или используйте access token:**

```bash
echo "ваш_docker_hub_access_token" | docker login --username ваш_username --password-stdin
```

### 4. Создайте директорию для проекта

```bash
sudo mkdir -p /opt/messenger
sudo chown -R $USER:$USER /opt/messenger
cd /opt/messenger
```

### 5. Скопируйте docker-compose.prod.yml

Скопируйте файл `docker-compose.prod.yml` из репозитория на сервер:

**Вариант A: Если репозиторий уже клонирован на сервере:**

```bash
cd /opt/messenger
cp docker-compose.prod.yml docker-compose.yml
```

**Вариант B: Если репозиторий не клонирован, создайте docker-compose.yml вручную:**

```bash
cd /opt/messenger
nano docker-compose.yml
```

Вставьте содержимое из `docker-compose.prod.yml` и замените `${DOCKER_USERNAME}` на ваш Docker Hub username (например, `alikakuznecova`):

```yaml
version: '3.8'

services:
  messenger-server:
    image: alikakuznecova/messenger-server:latest
    container_name: messenger-server
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - JWT_SECRET=ваш_секретный_ключ
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
      start_period: 40s
    networks:
      - messenger-network

networks:
  messenger-network:
    driver: bridge
```

**Важно:** Замените:
- `alikakuznecova` на ваш Docker Hub username
- `ваш_секретный_ключ` на случайную строку (сгенерируйте: `openssl rand -base64 32`)
- `https://ваш-домен.com` на ваш реальный домен или IP

### 6. Создайте директории для данных

```bash
cd /opt/messenger
mkdir -p data uploads public
```

### 7. Запустите контейнер в первый раз

```bash
cd /opt/messenger
docker compose pull
docker compose up -d
```

### 8. Проверьте, что всё работает

```bash
# Проверьте статус контейнера
docker compose ps

# Посмотрите логи
docker compose logs -f messenger-server

# Проверьте, что сервер отвечает
curl http://localhost:3000/health
```

## Что происходит при автоматическом деплое

Когда вы делаете `git push` в ветку `main`, GitHub Actions:

1. Собирает Docker образ
2. Публикует его в Docker Hub
3. Подключается к вашему серверу по SSH
4. Выполняет на сервере:
   ```bash
   cd /opt/messenger
   docker-compose pull  # Скачивает новый образ из Docker Hub
   docker-compose up -d  # Перезапускает контейнер с новым образом
   docker-compose exec -T messenger-server npm run migrate || true
   docker-compose restart messenger-server || true
   ```

## Важные моменты

1. **Docker Hub login:** Сервер должен быть залогинен в Docker Hub. Если вы перезагрузили сервер, возможно, нужно войти снова. Чтобы сделать это автоматически, можно настроить сохранение credentials (см. ниже).

2. **Образ должен быть публичным или сервер должен иметь доступ:** Если образ приватный, убедитесь, что сервер залогинен в Docker Hub с правильным аккаунтом.

3. **Переменные окружения:** Если нужно изменить переменные окружения, отредактируйте `docker-compose.yml` на сервере и выполните:
   ```bash
   docker compose up -d
   ```

## Автоматический Docker Hub login (опционально)

Чтобы не входить в Docker Hub каждый раз после перезагрузки сервера, можно настроить сохранение credentials:

```bash
# Создайте файл с credentials
mkdir -p ~/.docker
cat > ~/.docker/config.json << EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$(echo -n 'ваш_username:ваш_access_token' | base64)"
    }
  }
}
EOF
chmod 600 ~/.docker/config.json
```

**Или используйте Docker credential helper:**

```bash
# Установите docker-credential-helper
sudo apt-get install -y pass docker-credential-helper

# Настройте
mkdir -p ~/.docker
echo '{"credsStore": "pass"}' > ~/.docker/config.json
```

## Troubleshooting

### Ошибка "pull access denied"

Это означает, что сервер не залогинен в Docker Hub или образ приватный. Решение:

```bash
docker login
# Введите credentials
docker compose pull
```

### Ошибка "no such file or directory: docker-compose.yml"

Убедитесь, что файл `docker-compose.yml` находится в `/opt/messenger`:

```bash
cd /opt/messenger
ls -la docker-compose.yml
```

Если файла нет, создайте его (см. шаг 5 выше).

### Контейнер не запускается

Проверьте логи:

```bash
docker compose logs messenger-server
```

Убедитесь, что:
- Все переменные окружения установлены правильно
- Порты не заняты другими приложениями
- Директории `data`, `uploads`, `public` существуют и имеют правильные права

### Обновление не происходит

Проверьте, что:
1. GitHub Actions workflow выполнился успешно
2. Образ был опубликован в Docker Hub
3. На сервере выполните вручную:
   ```bash
   cd /opt/messenger
   docker compose pull
   docker compose up -d
   ```
