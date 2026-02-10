# HTTPS для messgo.duckdns.org — пошагово

Домен уже создан: **messgo.duckdns.org**. Дальше всё делается на **сервере** по SSH.

---

## 1. Убедиться, что DuckDNS указывает на IP сервера

- Зайдите на [duckdns.org](https://www.duckdns.org) → ваш поддомен `messgo`.
- В поле **Current IP** должен быть **IP вашего VPS**. Если там другой IP или пусто — вставьте IP сервера и нажмите Update.
- Проверка с вашего компьютера: в терминале выполните `ping messgo.duckdns.org` — должен отвечать ваш сервер.

---

## 2. Подключиться к серверу и установить nginx + Certbot

```bash
ssh root@ВАШ_IP
# или: ssh ubuntu@ВАШ_IP
```

Затем:

```bash
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

---

## 3. Создать конфиг nginx для messgo.duckdns.org

```bash
sudo nano /etc/nginx/sites-available/messenger
```

Вставьте **целиком** (без замены домена — уже подставлен messgo.duckdns.org):

```nginx
server {
    listen 80;
    server_name messgo.duckdns.org;

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

Сохраните: **Ctrl+O**, Enter, **Ctrl+X**.

---

## 4. Включить сайт и перезагрузить nginx

```bash
sudo ln -sf /etc/nginx/sites-available/messenger /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 5. Открыть порты 80 и 443

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

---

## 6. Получить бесплатный SSL‑сертификат (Let's Encrypt)

```bash
sudo certbot --nginx -d messgo.duckdns.org
```

- Введите **email** (для напоминаний о продлении).
- Согласитесь с условиями (Y).
- Certbot сам настроит HTTPS и редирект с http на https.

**Если при заходе по http:// звонок всё равно пишет «только по HTTPS»** — добавьте в начало конфига nginx отдельный блок редиректа (перед остальными `server`):

```nginx
server {
    listen 80;
    server_name messgo.duckdns.org;
    return 301 https://$host$request_uri;
}
```

Затем `sudo nginx -t` и `sudo systemctl reload nginx`.

---

## 7. Указать в приложении адрес по HTTPS

Откройте конфиг мессенджера:

```bash
nano /opt/messenger/server/.env
```

Найдите или добавьте строку (без слэша в конце):

```
APP_BASE_URL=https://messgo.duckdns.org
```

Сохраните (Ctrl+O, Enter, Ctrl+X) и перезапустите приложение:

```bash
pm2 restart messenger
```

---

## 8. Проверка

Откройте в браузере:

**https://messgo.duckdns.org**

Должен открыться мессенджер **без** предупреждения «Небезопасное соединение».

---

## Если что-то пошло не так

- **Certbot пишет «Connection refused» или «Timeout»** — проверьте, что на сервере запущен мессенджер (`pm2 status`), порт 3000 слушается, и что в DuckDNS указан правильный IP сервера.
- **Сайт не открывается** — проверьте `sudo nginx -t` и логи: `sudo tail -20 /var/log/nginx/error.log`.
- Подробнее про общую настройку HTTPS: [deploy-server.md](deploy-server.md), раздел 8.
