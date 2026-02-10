# Развёртывание сервера мессенджера на VPS

После аренды сервера выполните эти шаги **один раз**. Дальше при каждом пуше в `main` сервер будет обновляться автоматически.

---

## 1. Подключитесь к серверу по SSH

```bash
ssh root@ВАШ_IP
# или
ssh ubuntu@ВАШ_IP
```

(Используйте пользователя, который создали при заказе сервера.)

---

## 2. Установите Node.js, Git и PM2

**Ubuntu / Debian:**

```bash
# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Git
sudo apt-get install -y git

# PM2 (менеджер процессов, чтобы сервер перезапускался после обновлений)
sudo npm install -g pm2
```

Проверьте: `node -v` (должно быть v20.x), `git --version`, `pm2 -v`.

---

## 3. Клонируйте репозиторий

Если репозиторий **публичный**:

```bash
sudo mkdir -p /opt
sudo git clone https://github.com/ВАШ_ЛОГИН/messenger.git /opt/messenger
sudo chown -R $USER:$USER /opt/messenger
```

Если репозиторий **приватный**, настройте доступ по SSH-ключу или токену (см. раздел «Приватный репозиторий» ниже).

---

## 4. Настройте переменные окружения

```bash
cd /opt/messenger/server
cp .env.example .env
nano .env   # или vim
```

Заполните в `.env` минимум:

- **JWT_SECRET** — длинная случайная строка (например, сгенерируйте: `openssl rand -base64 32`).
- **PORT** — порт, на котором будет слушать приложение (например, 3000).
- **APP_BASE_URL** — полный адрес вашего сервера. Для защищённого доступа укажите **https://** (например, `https://messenger.ваш-домен.ru`). После настройки HTTPS (раздел 8) обновите эту переменную и перезапустите: `pm2 restart messenger`.
- **MESSENGER_DB_PATH** — путь к файлу базы данных (чаты и пользователи). **На сервере обязательно задайте**, чтобы данные не терялись при деплое: `MESSENGER_DB_PATH=/opt/messenger/data/messenger.db` (если репозиторий в другом каталоге — подставьте свой путь). Папка `data` создаётся при деплое автоматически.

По желанию настройте SMTP для писем сброса пароля (SMTP_HOST, SMTP_USER, SMTP_PASS, MAIL_FROM).

Сохраните файл (в nano: Ctrl+O, Enter, Ctrl+X).

---

## 5. Установите зависимости и запустите сервер

```bash
cd /opt/messenger/server
npm ci --omit=dev
pm2 start index.js --name messenger
pm2 save
pm2 startup   # выполните команду, которую выведет pm2 (для автозапуска после перезагрузки)
```

Проверьте: `pm2 status` — процесс `messenger` должен быть в статусе `online`. Логи: `pm2 logs messenger`.

---

## 5.1. Ручное обновление (пока автодеплой не подключён)

Пока GitHub Actions не подключается к серверу, можно подтягивать код вручную.

**Зайдите на сервер по SSH** и выполните один из вариантов.

**Вариант А — скрипт (из корня репозитория на сервере):**

```bash
cd /opt/messenger   # или ваш путь, если клонировали в другое место
bash scripts/update-on-server.sh
```

**Вариант Б — те же команды вручную:**

```bash
cd /opt/messenger
git fetch origin main
git reset --hard origin/main
cd server
npm ci --omit=dev
mkdir -p public
pm2 restart messenger || (pm2 start index.js --name messenger)
pm2 save
```

После этого код API и сервера обновлён. **Веб-клиент** (`server/public/`) при ручном обновлении не подтягивается из Git (его собирает CI). Если меняли папку `client/`, соберите локально: `cd client && flutter build web --release`, затем скопируйте на сервер: `scp -r build/web/* root@ВАШ_IP:/opt/messenger/server/public/` и на сервере выполните `pm2 restart messenger`.

---

## 6. Проверка в браузере

**Проверить, что API отвечает:**

1. Откройте порт 3000 на сервере (см. шаг 7 ниже).
2. В браузере откройте: **`http://ВАШ_IP:3000/health`**  
   Должен открыться ответ вроде: `{"ok":true}`. Значит сервер доступен.

**Открыть само приложение (логин, чаты) в браузере:**

На своём компьютере в папке проекта выполните:

```bash
cd client
flutter run -d chrome --dart-define=API_BASE_URL=http://ВАШ_IP:3000
```

Подставьте вместо `ВАШ_IP` реальный IP или домен сервера. Откроется Chrome с мессенджером, который уже ходит на ваш сервер — можно регистрироваться и проверять работу.

**Чтобы приложение открывалось по адресу `http://ВАШ_IP:3000/`** (без команды с `--dart-define`), на сервер нужно один раз выложить веб-клиент:

**Вариант А — автоматически:** сделайте `git push origin main`. Workflow соберёт Flutter web и зальёт файлы в `server/public/` на сервере. После успешного деплоя откройте в браузере `http://ВАШ_IP:3000/`.

**Вариант Б — вручную один раз:** на своём компьютере выполните:
```bash
cd client
flutter build web --release
scp -r build/web/* root@ВАШ_IP:/opt/messenger/server/public/
```
(подставьте пользователя и IP сервера). Затем на сервере: `pm2 restart messenger`. После этого `http://ВАШ_IP:3000/` будет открывать приложение.

---

## 7. Откройте порт в файрволе

Если на сервере включён ufw:

```bash
sudo ufw allow 3000/tcp   # или тот порт, что указали в .env
sudo ufw allow 22/tcp    # SSH
sudo ufw enable
```

---

## 8. Включение HTTPS (защищённое соединение)

Чтобы сайт открывался по **https://**, перед приложением ставят обратный прокси (nginx), который принимает HTTPS и отдаёт запросы Node по HTTP на localhost. Сертификат берётся бесплатно у **Let's Encrypt** (нужен **домен**, указывающий на ваш сервер).

### 8.1. Требования

- У вас есть **домен** (например `messenger.example.com`), и в DNS у него указан **A-запись** на IP вашего сервера.
- Порт **80** на сервере открыт (для проверки Let's Encrypt при выдаче сертификата).

### 8.2. Установка nginx и Certbot (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### 8.3. Выдача сертификата и базовая настройка nginx

Certbot может сам настроить nginx и получить сертификат. Сначала создайте конфиг сайта:

```bash
sudo nano /etc/nginx/sites-available/messenger
```

Вставьте (подставьте свой домен вместо `messenger.example.com`):

```nginx
server {
    listen 80;
    server_name messenger.example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Редирект HTTP → HTTPS (обязательно для видеозвонков в браузере):** после настройки HTTPS (после certbot) убедитесь, что запросы по `http://` перенаправляются на `https://`. Certbot обычно добавляет это сам. Если при заходе по `http://` звонок пишет «только по HTTPS» — добавьте в nginx **отдельный** блок в начале конфига (перед основным `server`):

```nginx
server {
    listen 80;
    server_name messenger.example.com;
    return 301 https://$host$request_uri;
}
```

Сохраните (Ctrl+O, Enter, Ctrl+X). Включите сайт и проверьте конфиг:

```bash
sudo ln -sf /etc/nginx/sites-available/messenger /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

Откройте порт 80 в файрволе, если ещё не открыт:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

Получите сертификат и автоматическую настройку HTTPS в nginx:

```bash
sudo certbot --nginx -d messenger.example.com
```

Укажите email для уведомлений Let's Encrypt, примите условия. Certbot добавит в конфиг редирект с HTTP на HTTPS и путь к сертификатам.

Проверьте: откройте в браузере **https://messenger.example.com** — должен открыться мессенджер без предупреждений о незащищённом соединении.

### 8.4. Переменные окружения приложения

В `server/.env` укажите полный адрес по **HTTPS**:

```bash
APP_BASE_URL=https://messenger.example.com
```

После изменения перезапустите приложение:

```bash
pm2 restart messenger
```

### 8.5. Продление сертификата

Let's Encrypt выдаёт сертификаты на 90 дней. Продление обычно настраивается автоматически. Проверить таймер можно так:

```bash
sudo certbot renew --dry-run
```

### 8.6. HTTPS без покупки домена

Два варианта: **бесплатный поддомен** (рекомендуется) или **только по IP** с самоподписанным сертификатом.

---

#### Вариант А: Бесплатный поддомен + Let's Encrypt (рекомендуется)

Домен покупать не нужно. Сервисы вроде **DuckDNS**, **No-IP**, **Afraid.org** дают бесплатный поддомен (например `mymessenger.duckdns.org`), который указывает на IP вашего сервера. После этого можно получить бесплатный сертификат Let's Encrypt — браузер не будет показывать предупреждений.

**Шаги (на примере DuckDNS):**

1. Зайдите на [duckdns.org](https://www.duckdns.org), войдите через Google/GitHub и создайте поддомен (например `mymessenger`). Получите имя вида `mymessenger.duckdns.org` и токен для обновления IP.
2. В панели управления вашего VPS/DNS настройте **A-запись** для этого имени на IP сервера (если DuckDNS сам обновляет IP по токену — просто сохраните поддомен, он привяжется к вашему IP при первом заходе).
3. На сервере установите nginx и certbot (см. разделы 8.2 и 8.3 выше), в конфиге nginx укажите `server_name mymessenger.duckdns.org;`.
4. Откройте порты 80 и 443, выполните:
   ```bash
   sudo certbot --nginx -d mymessenger.duckdns.org
   ```
5. В `server/.env` укажите: `APP_BASE_URL=https://mymessenger.duckdns.org`, затем `pm2 restart messenger`.

В браузере сайт будет открываться по **https://** без предупреждений. Продление сертификата — автоматическое.

---

#### Вариант Б: Только IP — самоподписанный сертификат

Если не хотите использовать даже бесплатный поддомен, можно включить HTTPS по **IP** с самоподписанным сертификатом. Трафик будет шифроваться, но при первом заходе браузер покажет предупреждение («Ваше подключение не защищено»). Нужно нажать «Дополнительно» → «Перейти на сайт (небезопасно)». Для личного использования этого достаточно.

**На сервере:**

1. Установите nginx (если ещё не установлен):
   ```bash
   sudo apt-get update
   sudo apt-get install -y nginx
   ```

2. Создайте папку для сертификата и сгенерируйте самоподписанный сертификат (подставьте свой IP вместо `123.45.67.89`):
   ```bash
   sudo mkdir -p /etc/nginx/ssl
   sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout /etc/nginx/ssl/messenger.key \
     -out /etc/nginx/ssl/messenger.crt \
     -subj "/CN=123.45.67.89" \
     -addext "subjectAltName=IP:123.45.67.89"
   ```

3. Создайте конфиг nginx (замените `123.45.67.89` на IP вашего сервера):
   ```bash
   sudo nano /etc/nginx/sites-available/messenger
   ```
   Содержимое:
   ```nginx
   server {
       listen 443 ssl;
       server_name 123.45.67.89;

       ssl_certificate     /etc/nginx/ssl/messenger.crt;
       ssl_certificate_key /etc/nginx/ssl/messenger.key;

       location / {
           proxy_pass http://127.0.0.1:3000;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

4. Включите сайт и перезапустите nginx:
   ```bash
   sudo ln -sf /etc/nginx/sites-available/messenger /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

5. Откройте порт 443:
   ```bash
   sudo ufw allow 443/tcp
   sudo ufw reload
   ```

6. В `server/.env` укажите:
   ```bash
   APP_BASE_URL=https://123.45.67.89
   ```
   Выполните `pm2 restart messenger`.

Откройте в браузере **https://123.45.67.89**. При предупреждении выберите «Дополнительно» → «Перейти на сайт». Соединение будет зашифровано.

---

## 9. Настройте автодеплой из GitHub

При пуше в ветку `main` сервер будет обновляться сам. Нужно один раз добавить секреты в репозитории.

1. Откройте репозиторий на GitHub → **Settings** → **Secrets and variables** → **Actions**.
2. Нажмите **New repository secret** и добавьте:

| Имя              | Значение |
|------------------|----------|
| `DEPLOY_HOST`    | IP или домен вашего сервера (например, `123.45.67.89`) |
| `DEPLOY_USER`    | Пользователь SSH (например, `root` или `ubuntu`) |
| `DEPLOY_SSH_KEY` | **Приватный** SSH-ключ, которым вы подключаетесь к серверу |

**Как получить приватный ключ:** на своём компьютере откройте файл ключа (например, `~/.ssh/id_rsa` или `~/.ssh/id_ed25519`) и скопируйте **весь** текст, включая строки `-----BEGIN ... KEY-----` и `-----END ... KEY-----`. Вставьте в секрет `DEPLOY_SSH_KEY`.

3. (Необязательно.) Если клонировали репозиторий не в `/opt/messenger`, добавьте секрет `DEPLOY_PATH` с путём к папке (например, `/home/ubuntu/messenger`).

После этого при каждом `git push origin main` workflow **Deploy server** подключится к серверу, выполнит `git pull`, `npm ci` и перезапустит приложение через PM2.

**Если в логе деплоя ошибка `unable to authenticate` или `no supported methods remain`:**

1. **В секрет `DEPLOY_SSH_KEY` должен попасть именно приватный ключ** (файл без `.pub`). Публичный ключ (`id_rsa.pub` / `id_ed25519.pub`) в секрет не подставлять.
2. Копируйте ключ целиком: от `-----BEGIN ... KEY-----` до `-----END ... KEY-----` включительно, без лишних пробелов в начале/конце и без лишних переносов строк в начале.
3. На сервере должен быть добавлен **публичный** ключ в `~/.ssh/authorized_keys` того пользователя, который указан в `DEPLOY_USER`. Проверка: на своём ПК `cat ~/.ssh/id_ed25519.pub` (или `id_rsa.pub`) — этот вывод должен быть одной строкой в `authorized_keys` на сервере. На сервере: `cat ~/.ssh/authorized_keys`.
4. У ключа не должно быть пароля (passphrase), иначе деплой не сможет его использовать. Если пароль есть, создайте новый ключ без пароля: `ssh-keygen -t ed25519 -f deploy_key -N ""`, добавьте `deploy_key.pub` на сервер в `authorized_keys`, а содержимое файла `deploy_key` (приватный) — в секрет `DEPLOY_SSH_KEY`.
5. Проверьте `DEPLOY_USER`: это тот пользователь, под которым вы заходите по SSH (например `root` или `ubuntu`). И `DEPLOY_HOST` — IP или домен без `http://` и без порта.

---

## 10. Приватный репозиторий

Если репозиторий закрытый, на сервере нужен доступ к GitHub по SSH или по токену.

**Вариант A — deploy-ключ (рекомендуется):**

1. На своём компьютере: `ssh-keygen -t ed25519 -C "deploy" -f deploy_key` (пароль можно не ставить).
2. Добавьте **публичный** ключ `deploy_key.pub` в GitHub: репозиторий → **Settings** → **Deploy keys** → Add deploy key.
3. На сервере:
   ```bash
   mkdir -p ~/.ssh
   nano ~/.ssh/id_ed25519   # вставьте содержимое файла deploy_key (приватный ключ)
   chmod 600 ~/.ssh/id_ed25519
   ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
   git clone git@github.com:ВАШ_ЛОГИН/messenger.git /opt/messenger
   ```

**Вариант B — HTTPS с токеном:**

```bash
git clone https://ВАШ_ТОКЕН@github.com/ВАШ_ЛОГИН/messenger.git /opt/messenger
```

(Токен: GitHub → Settings → Developer settings → Personal access tokens, права `repo`.)

---

## Чаты/сообщения не сохраняются

Если после перезагрузки страницы чаты и сообщения пропадают:

1. Зайдите на сервер по SSH и откройте `server/.env`.
2. Добавьте (или измените) строку с путём к базе **вне** папки с кодом, чтобы деплой её не затирал:
   ```bash
   MESSENGER_DB_PATH=/opt/messenger/data/messenger.db
   ```
   Подставьте свой путь к репозиторию вместо `/opt/messenger`, если клонировали в другое место.
3. Создайте папку и перенесите базу (если она уже была в `server/`):
   ```bash
   mkdir -p /opt/messenger/data
   cp /opt/messenger/server/messenger.db /opt/messenger/data/messenger.db
   ```
4. Перезапустите приложение: `pm2 restart messenger`.

После следующих деплоев папка `data` не трогается, база сохраняется.

---

## Сайт не открывается с Windows или в другом браузере

Если по той же ссылке сайт открывается на Mac/телефоне, но на Windows (например в Chrome) пишет «Не удается получить доступ к сайту»:

1. **Проверьте DNS** — на проблемном компьютере выполните в командной строке: `ping ваш-домен.ru`. Если пинг не проходит, проблема в сети или DNS на этой машине/сети.
2. **Файрвол и антивирус** — временно отключите или добавьте сайт в исключения; корпоративные файрволы часто блокируют нестандартные порты или домены.
3. **Другой браузер** — попробуйте Edge или Firefox на том же Windows: если в них сайт открывается, дело в настройках Chrome (расширения, «безопасный просмотр»).
4. **HTTPS и сертификат** — если используете самоподписанный сертификат, Windows/Chrome могут блокировать доступ. Для продакшена используйте бесплатный сертификат Let's Encrypt (раздел про HTTPS выше).
5. **Очистка кэша** — в Chrome: Настройки → Конфиденциальность → Очистить данные (кэш и cookie для этого сайта).

Серверная часть не различает Mac и Windows; разница только в сети, DNS, браузере или файрволе на стороне клиента.

---

## Полезные команды на сервере

- Статус: `pm2 status`
- Логи: `pm2 logs messenger`
- Перезапуск вручную: `pm2 restart messenger`
- Остановка: `pm2 stop messenger`

База данных: по умолчанию `server/messenger.db`; при настройке `MESSENGER_DB_PATH` — указанный файл (например `data/messenger.db`). Загрузки: `server/uploads/`. Регулярно делайте бэкап этих данных.
