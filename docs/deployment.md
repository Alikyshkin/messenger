# Развёртывание сервера

Полное руководство по развёртыванию мессенджера на продакшн сервере.

## Содержание

- [Выбор метода развёртывания](#выбор-метода-развёртывания)
- [Docker (рекомендуется)](#docker-рекомендуется)
- [VPS с PM2](#vps-с-pm2)
- [Настройка HTTPS](#настройка-https)
- [Миграция с PM2 на Docker](#миграция-с-pm2-на-docker)
- [Автоматический деплой](#автоматический-деплой)
- [Troubleshooting](#troubleshooting)

---

## Выбор метода развёртывания

### Docker (рекомендуется)
✅ Изолированное окружение  
✅ Простое обновление  
✅ Автоматический деплой через GitHub Actions  
✅ Легко масштабировать  

### PM2 (традиционный)
✅ Прямой контроль над процессом  
✅ Меньше накладных расходов  
✅ Подходит для простых VPS  

---

## Docker (рекомендуется)

### Быстрый старт

1. **Установите Docker и Docker Compose** на сервере:

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt-get install -y docker-compose-plugin
sudo usermod -aG docker $USER
```

2. **Войдите в Docker Hub** на сервере:

```bash
docker login
# Введите ваш Docker Hub username и password (или access token)
```

3. **Создайте директорию для проекта**:

```bash
sudo mkdir -p /opt/messenger
sudo chown -R $USER:$USER /opt/messenger
cd /opt/messenger
```

4. **Создайте `docker-compose.yml`**:

```yaml
version: '3.8'

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
- `${DOCKER_USERNAME}` на ваш Docker Hub username
- `ваш_секретный_ключ` на случайную строку (сгенерируйте: `openssl rand -base64 32`)
- `https://ваш-домен.com` на ваш реальный домен или IP

5. **Создайте директории для данных**:

```bash
mkdir -p data uploads public
```

6. **Запустите контейнер**:

```bash
docker compose pull
docker compose up -d
```

7. **Проверьте статус**:

```bash
docker compose ps
docker compose logs -f messenger-server
curl http://localhost:3000/health
```

### Обновление

При автоматическом деплое через GitHub Actions контейнер обновляется автоматически. Для ручного обновления:

```bash
cd /opt/messenger
docker compose pull
docker compose up -d
```

### Volumes

- `./data` - база данных SQLite
- `./uploads` - загруженные файлы
- `./public` - статические файлы (web client)

---

## VPS с PM2

### Установка зависимостей

```bash
# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs git

# PM2 (менеджер процессов)
sudo npm install -g pm2
```

### Клонирование репозитория

```bash
sudo mkdir -p /opt
sudo git clone https://github.com/ВАШ_ЛОГИН/messenger.git /opt/messenger
sudo chown -R $USER:$USER /opt/messenger
```

### Настройка переменных окружения

```bash
cd /opt/messenger/server
cp .env.example .env
nano .env
```

Минимальные настройки:

```env
JWT_SECRET=ваш_секретный_ключ
PORT=3000
APP_BASE_URL=https://ваш-домен.com
MESSENGER_DB_PATH=/opt/messenger/data/messenger.db
```

### Запуск

```bash
cd /opt/messenger/server
npm ci --omit=dev
pm2 start index.js --name messenger
pm2 save
pm2 startup  # выполните команду, которую выведет pm2
```

### Ручное обновление

```bash
cd /opt/messenger
git fetch origin main
git reset --hard origin/main
cd server
npm ci --omit=dev
pm2 restart messenger
pm2 save
```

---

## Настройка HTTPS

### Требования

- Домен, указывающий на ваш сервер (A-запись в DNS)
- Открытые порты 80 и 443

### Установка nginx и Certbot

```bash
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### Настройка nginx

Создайте конфиг `/etc/nginx/sites-available/messenger`:

```nginx
server {
    listen 80;
    server_name ваш-домен.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

Включите сайт:

```bash
sudo ln -sf /etc/nginx/sites-available/messenger /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Получение SSL сертификата

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo certbot --nginx -d ваш-домен.com
```

Certbot автоматически настроит HTTPS и редирект с HTTP на HTTPS.

### Обновление переменных окружения

В `server/.env` или `docker-compose.yml`:

```env
APP_BASE_URL=https://ваш-домен.com
```

Перезапустите приложение:

```bash
# PM2
pm2 restart messenger

# Docker
docker compose restart messenger-server
```

### Бесплатный поддомен (DuckDNS)

Если у вас нет домена, используйте бесплатный поддомен:

1. Зарегистрируйтесь на [duckdns.org](https://www.duckdns.org)
2. Создайте поддомен (например, `mymessenger`)
3. Убедитесь, что поддомен указывает на IP вашего сервера
4. Используйте поддомен в настройке nginx и certbot:

```bash
sudo certbot --nginx -d mymessenger.duckdns.org
```

---

## Миграция с PM2 на Docker

Если у вас уже запущено приложение через PM2:

### Шаг 1: Остановите PM2

```bash
pm2 stop messenger
pm2 delete messenger
pm2 save
pm2 unstartup  # отключите автозапуск PM2
```

### Шаг 2: Настройте Docker

Следуйте инструкциям в разделе [Docker](#docker-рекомендуется) выше.

### Шаг 3: Проверьте миграцию

```bash
# PM2 не должен быть запущен
pm2 status

# Docker контейнер должен работать
docker compose ps

# Проверьте порт
netstat -tulpn | grep 3000
```

### Важные моменты

- **Данные сохраняются:** Volumes в Docker используют те же директории (`./data`, `./uploads`, `./public`)
- **Переменные окружения:** Убедитесь, что в `docker-compose.yml` настроены все нужные переменные из `.env`
- **Автозапуск:** Docker Compose с `restart: unless-stopped` автоматически перезапускает контейнер после перезагрузки сервера

---

## Автоматический деплой

### Настройка GitHub Actions

1. Добавьте секреты в GitHub: `Settings` → `Secrets and variables` → `Actions`

| Имя | Значение |
|-----|----------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub access token |
| `DEPLOY_HOST` | IP или домен сервера |
| `DEPLOY_USER` | SSH пользователь (например, `root`) |
| `DEPLOY_SSH_KEY` | Приватный SSH ключ |

2. При пуше в `main` автоматически:
   - Собирается Docker образ
   - Публикуется в Docker Hub
   - Подключается к серверу по SSH
   - Обновляет контейнер

### Настройка сервера для автоматического деплоя

См. [Настройка секретов](setup-secrets.md) для подробной инструкции.

---

## Troubleshooting

### Контейнер не запускается

```bash
# Проверьте логи
docker compose logs messenger-server

# Убедитесь, что:
# - Все переменные окружения установлены правильно
# - Порты не заняты другими приложениями
# - Директории существуют и имеют правильные права
```

### Ошибка "pull access denied"

Сервер не залогинен в Docker Hub:

```bash
docker login
docker compose pull
```

### Сайт не открывается

1. Проверьте статус приложения:
   ```bash
   # PM2
   pm2 status
   
   # Docker
   docker compose ps
   ```

2. Проверьте nginx:
   ```bash
   sudo nginx -t
   sudo tail -20 /var/log/nginx/error.log
   ```

3. Проверьте порты:
   ```bash
   sudo ufw status
   netstat -tulpn | grep 3000
   ```

### Чаты/сообщения не сохраняются

Убедитесь, что `MESSENGER_DB_PATH` указывает на постоянную директорию:

```env
MESSENGER_DB_PATH=/opt/messenger/data/messenger.db
```

Создайте директорию и перенесите базу:

```bash
mkdir -p /opt/messenger/data
cp /opt/messenger/server/messenger.db /opt/messenger/data/messenger.db
```

### HTTPS не работает

1. Проверьте DNS: `ping ваш-домен.com`
2. Проверьте сертификат: `sudo certbot certificates`
3. Проверьте редирект HTTP → HTTPS в nginx конфиге
4. Убедитесь, что `APP_BASE_URL` использует `https://`

---

## Полезные команды

### PM2

```bash
pm2 status              # Статус процессов
pm2 logs messenger      # Логи
pm2 restart messenger   # Перезапуск
pm2 stop messenger      # Остановка
```

### Docker

```bash
docker compose ps                    # Статус контейнеров
docker compose logs -f messenger-server  # Логи
docker compose restart messenger-server # Перезапуск
docker compose down                   # Остановка
docker compose pull                  # Обновление образа
```

### Nginx

```bash
sudo nginx -t                        # Проверка конфига
sudo systemctl reload nginx          # Перезагрузка
sudo tail -f /var/log/nginx/error.log # Логи ошибок
```

### Certbot

```bash
sudo certbot renew --dry-run         # Тест продления
sudo certbot certificates            # Список сертификатов
```
