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
- **APP_BASE_URL** — полный адрес вашего сервера (например, `https://api.ваш-домен.ru` или `https://ВАШ_IP`).
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

## 8. Настройте автодеплой из GitHub

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

## 9. Приватный репозиторий

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

## Полезные команды на сервере

- Статус: `pm2 status`
- Логи: `pm2 logs messenger`
- Перезапуск вручную: `pm2 restart messenger`
- Остановка: `pm2 stop messenger`

База данных: по умолчанию `server/messenger.db`; при настройке `MESSENGER_DB_PATH` — указанный файл (например `data/messenger.db`). Загрузки: `server/uploads/`. Регулярно делайте бэкап этих данных.
