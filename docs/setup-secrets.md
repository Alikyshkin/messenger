# Настройка секретов для GitHub Actions

Эта инструкция поможет вам получить все необходимые секреты для автоматического деплоя.

## 1. Docker Hub аккаунт и токен

### Шаг 1: Создайте аккаунт на Docker Hub (если его нет)

1. Перейдите на https://hub.docker.com/
2. Нажмите `Sign Up` и создайте бесплатный аккаунт
3. Запомните ваш **username** (например, `alikyshkin`)

### Шаг 2: Создайте Access Token

1. Войдите в Docker Hub
2. Нажмите на ваш username в правом верхнем углу → `Account Settings`
3. В левом меню выберите `Security`
4. Нажмите `New Access Token`
5. Введите название токена (например, `github-actions-messenger`)
6. Выберите права: `Read, Write & Delete`
7. Нажмите `Generate`
8. **ВАЖНО:** Скопируйте токен сразу! Он показывается только один раз. Выглядит примерно так: `dckr_pat_xxxxxxxxxxxxxxxxxxxx`

**Что вам нужно:**
- `DOCKER_USERNAME` = ваш username на Docker Hub (например, `alikyshkin`)
- `DOCKER_PASSWORD` = созданный access token (например, `dckr_pat_xxxxxxxxxxxxxxxxxxxx`)

---

## 2. SSH ключ для подключения к серверу

### Вариант A: Если у вас уже есть SSH ключ

На вашем MacBook выполните:

```bash
# Проверьте, есть ли у вас SSH ключ
ls -la ~/.ssh/

# Если есть файлы id_rsa или id_ed25519, используйте их
# Покажите публичный ключ (чтобы добавить на сервер)
cat ~/.ssh/id_rsa.pub
# или
cat ~/.ssh/id_ed25519.pub
```

**Если ключа нет**, создайте новый:

```bash
# Создайте новый SSH ключ
ssh-keygen -t ed25519 -C "github-actions-deploy"

# Нажмите Enter для сохранения в стандартное место (~/.ssh/id_ed25519)
# Введите пароль (или оставьте пустым для автоматического деплоя)
# Покажите публичный ключ
cat ~/.ssh/id_ed25519.pub
```

### Шаг 2: Добавьте публичный ключ на сервер

1. Скопируйте содержимое публичного ключа (вывод команды `cat ~/.ssh/id_ed25519.pub`)
2. Подключитесь к вашему серверу:
   ```bash
   ssh ваш_пользователь@ваш_сервер
   ```
3. На сервере выполните:
   ```bash
   # Создайте директорию .ssh, если её нет
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   
   # Добавьте публичный ключ
   echo "ваш_публичный_ключ" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

### Шаг 3: Получите приватный ключ для GitHub

На вашем MacBook:

```bash
# Покажите приватный ключ (полностью, включая BEGIN и END строки)
cat ~/.ssh/id_ed25519
```

Скопируйте весь вывод, включая строки:
```
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

**Что вам нужно:**
- `DEPLOY_SSH_KEY` = полный приватный ключ (весь вывод `cat ~/.ssh/id_ed25519`)

---

## 3. Информация о сервере

Вам нужно знать:

- **IP адрес или домен сервера** (например, `192.168.1.100` или `myserver.com`)
- **SSH пользователь** (обычно `root` или `deploy`)

**Что вам нужно:**
- `DEPLOY_HOST` = IP или домен вашего сервера
- `DEPLOY_USER` = SSH пользователь на сервере

---

## 4. Добавление секретов в GitHub

1. Откройте ваш репозиторий на GitHub
2. Перейдите в `Settings` (вверху справа)
3. В левом меню выберите `Secrets and variables` → `Actions`
4. Нажмите `New repository secret`

Добавьте каждый секрет отдельно:

### Секрет 1: DOCKER_USERNAME
- **Name:** `DOCKER_USERNAME`
- **Secret:** ваш Docker Hub username (например, `alikyshkin`)

### Секрет 2: DOCKER_PASSWORD
- **Name:** `DOCKER_PASSWORD`
- **Secret:** ваш Docker Hub access token (например, `dckr_pat_xxxxxxxxxxxxxxxxxxxx`)

### Секрет 3: DEPLOY_HOST
- **Name:** `DEPLOY_HOST`
- **Secret:** IP или домен вашего сервера (например, `192.168.1.100`)

### Секрет 4: DEPLOY_USER
- **Name:** `DEPLOY_USER`
- **Secret:** SSH пользователь (например, `root`)

### Секрет 5: DEPLOY_SSH_KEY
- **Name:** `DEPLOY_SSH_KEY`
- **Secret:** полный приватный SSH ключ (весь вывод `cat ~/.ssh/id_ed25519`)

---

## 5. Проверка

После добавления всех секретов:

1. Перейдите в `Actions` в вашем репозитории
2. Найдите workflow `Deploy`
3. Нажмите `Run workflow` → `Run workflow`
4. Проверьте, что deployment проходит успешно

---

## Быстрая проверка SSH подключения

Перед добавлением секретов проверьте, что SSH работает:

```bash
# На вашем MacBook
ssh -i ~/.ssh/id_ed25519 ваш_пользователь@ваш_сервер

# Если подключение успешно, значит всё настроено правильно
```

---

## Troubleshooting

### SSH не работает
- Убедитесь, что публичный ключ добавлен в `~/.ssh/authorized_keys` на сервере
- Проверьте права доступа: `chmod 600 ~/.ssh/authorized_keys`
- Убедитесь, что SSH сервис запущен на сервере: `sudo systemctl status ssh`

### Docker Hub токен не работает
- Убедитесь, что токен имеет права `Read, Write & Delete`
- Проверьте, что токен скопирован полностью (без пробелов в начале/конце)
- Если токен потерян, создайте новый в Docker Hub → Account Settings → Security

### Deployment падает с ошибкой
- Проверьте логи в GitHub Actions: `Actions` → выберите failed workflow → посмотрите логи
- Убедитесь, что все 5 секретов добавлены правильно
- Проверьте, что на сервере есть директория `/opt/messenger` и файл `docker-compose.yml`
