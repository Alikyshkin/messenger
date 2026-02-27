# Развёртывание на VPS

## Архитектура

```
Интернет (443 HTTPS / 80 HTTP)
        │
     [nginx]
        ├── /ws, /auth, /contacts, ...  →  proxy_pass http://127.0.0.1:3000
        └── всё остальное               →  /opt/messenger/public/ (Flutter web)

[Node.js] — управляется через PM2 (автозапуск, рестарт при крашах)
[PM2]     — управляется через systemd (выживает при ребуте сервера)

GitHub Actions (при push в main):
  1. Собирает Flutter web на CI (бесплатные раннеры GitHub)
  2. rsync → заливает билд в /opt/messenger/public/ на сервере
  3. SSH: git pull + npm ci + pm2 restart messenger
```

## Первичная настройка сервера

### 1. Установить Node.js 20

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 2. Установить PM2

```bash
sudo npm install -g pm2
```

### 3. Клонировать репозиторий

```bash
sudo mkdir -p /opt/messenger
sudo chown $USER:$USER /opt/messenger
git clone git@github.com:ВАШ_ЮЗЕ/messenger.git /opt/messenger
```

### 4. Создать .env

```bash
cat > /opt/messenger/server/.env << 'EOF'
NODE_ENV=production
PORT=3000
TRUST_PROXY=true
JWT_SECRET=<длинная_случайная_строка>
APP_BASE_URL=https://ваш-домен.com
CORS_ORIGINS=https://ваш-домен.com
LOG_LEVEL=info
EOF
```

### 5. Установить зависимости

```bash
cd /opt/messenger/server
npm ci --omit=dev
```

### 6. Создать папку для Flutter-билда

```bash
mkdir -p /opt/messenger/public
```

GitHub Actions будет заливать в неё собранный Flutter web через rsync при каждом деплое.

### 7. Запустить Node.js через PM2

```bash
cd /opt/messenger/server
pm2 start index.js --name messenger
pm2 save

# Настроить автозапуск PM2 при ребуте сервера
pm2 startup
# Выполнить команду, которую выдаст pm2 startup (начинается с sudo env PATH=...)
```

Проверить:

```bash
pm2 status
curl http://localhost:3000/health
```

## Настройка nginx

### Установить

```bash
sudo apt-get install -y nginx
```

### Создать конфиг

```bash
sudo tee /etc/nginx/sites-available/messenger > /dev/null << 'NGINXEOF'
server {
    listen 80;
    server_name ваш-домен.com;

    root /opt/messenger/public;
    index index.html;

    # Flutter статика — кешируется навсегда (Flutter хеширует имена файлов)
    location ~* \.(js|css|wasm|png|jpg|ico|svg|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # WebSocket
    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
    }

    # API — проксируем на Node.js
    location ~ ^/(auth|contacts|messages|chats|groups|users|polls|search|export|media|uploads|sync|version|health)(/|$) {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # SPA fallback — всё остальное отдаём index.html для Flutter-роутера
    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINXEOF

sudo ln -s /etc/nginx/sites-available/messenger /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

## HTTPS через certbot

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d ваш-домен.com
```

Certbot автоматически изменит конфиг nginx и настроит автопродление сертификата.

## Автодеплой через GitHub Actions

При каждом `push` в ветку `main` запускается `.github/workflows/deploy.yml`:

1. Собирает Flutter web на CI-раннере GitHub (Flutter на сервере не нужен)
2. Заливает `client/build/web/` на сервер через `rsync`
3. Подключается по SSH и выполняет:
   ```bash
   cd /opt/messenger && git pull
   cd server && npm ci --omit=dev
   npm run migrate
   pm2 restart messenger
   ```

Настройка секретов — см. [setup-secrets.md](setup-secrets.md).

## Ручное обновление (если нет CI)

```bash
# SSH на сервер, затем:
cd /opt/messenger && bash scripts/update-on-server.sh
```

## Обслуживание

```bash
# Логи сервера
pm2 logs messenger

# Статус процессов
pm2 status

# Рестарт сервера
pm2 restart messenger

# Логи nginx
sudo tail -f /var/log/nginx/error.log

# Статус nginx
sudo systemctl status nginx
```

## Troubleshooting

**Сервер не запускается**
- `pm2 logs messenger` — смотреть ошибки
- Проверить `.env`: все обязательные переменные заполнены?
- Проверить права на папку с БД

**Сайт недоступен (ERR_CONNECTION_REFUSED)**
- `sudo nginx -t` — синтаксис конфига
- `sudo systemctl status nginx` — запущен ли nginx
- `pm2 status` — запущен ли Node.js
- Проверить, что `server_name` в nginx совпадает с реальным доменом
- Firewall: открыты ли порты 80 и 443? (`ufw status`)

**Flutter не загружается (пустая страница)**
- Проверить, что в `/opt/messenger/public/` есть файлы (GitHub Actions задеплоил билд?)
- `curl https://ваш-домен.com/` — что отдаёт сервер?

**WebSocket не подключается**
- Убедиться, что в nginx есть блок `location /ws` с заголовками `Upgrade` и `Connection`
- Проверить, что `APP_BASE_URL` в `.env` совпадает с реальным URL

**После ребута сервера приложение не поднимается**
- Проверить, что выполнялся `pm2 startup` и `pm2 save`
- `sudo systemctl status pm2-root` — работает ли systemd-unit для PM2
