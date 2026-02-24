# Настройка секретов для GitHub Actions

Нужны для автоматического деплоя (Docker Hub + SSH).

## 1. Docker Hub

1. [hub.docker.com](https://hub.docker.com/) → Sign Up / войти.
2. Account Settings → Security → New Access Token, права: Read, Write & Delete. Скопировать токен один раз.
3. **Секреты:** `DOCKER_USERNAME` = username, `DOCKER_PASSWORD` = access token.

## 2. SSH ключ для сервера

```bash
# Проверка: ls ~/.ssh/
# Создать при необходимости:
ssh-keygen -t ed25519 -C "github-actions-deploy"
cat ~/.ssh/id_ed25519.pub   # добавить на сервер в ~/.ssh/authorized_keys
cat ~/.ssh/id_ed25519       # целиком → секрет DEPLOY_SSH_KEY
```

На сервере: `mkdir -p ~/.ssh && echo "ваш_публичный_ключ" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`.

## 3. Секреты репозитория

GitHub → репозиторий → Settings → Secrets and variables → Actions → New repository secret:

| Имя | Значение |
|-----|----------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub access token |
| `DEPLOY_HOST` | IP или домен сервера |
| `DEPLOY_USER` | SSH пользователь (например `root`) |
| `DEPLOY_SSH_KEY` | Приватный ключ (вывод `cat ~/.ssh/id_ed25519`) |

## Проверка

Actions → Deploy → Run workflow. Перед этим: на сервере должна быть папка `/opt/messenger` и `docker-compose.yml` (см. [deployment.md](deployment.md)).

**Troubleshooting:** SSH — проверить `authorized_keys` и права; Docker — токен с правами Read/Write/Delete; деплой — логи в Actions, наличие всех 5 секретов.
