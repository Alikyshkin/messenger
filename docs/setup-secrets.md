# Настройка секретов для GitHub Actions

Нужны для автоматического деплоя по SSH.

## SSH ключ для сервера

```bash
# Проверка: ls ~/.ssh/
# Создать при необходимости:
ssh-keygen -t ed25519 -C "github-actions-deploy"
cat ~/.ssh/id_ed25519.pub   # добавить на сервер в ~/.ssh/authorized_keys
cat ~/.ssh/id_ed25519       # целиком → секрет DEPLOY_SSH_KEY
```

На сервере: `mkdir -p ~/.ssh && echo "ваш_публичный_ключ" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`.

## Секреты репозитория

GitHub → репозиторий → Settings → Secrets and variables → Actions → New repository secret:

| Имя | Значение |
|-----|----------|
| `DEPLOY_HOST` | IP или домен сервера |
| `DEPLOY_USER` | SSH пользователь (например `root`) |
| `DEPLOY_SSH_KEY` | Приватный ключ (вывод `cat ~/.ssh/id_ed25519`) |

## Проверка

Actions → Deploy → Run workflow.

**Troubleshooting:** SSH — проверить `authorized_keys` и права; деплой — логи в Actions, наличие всех 3 секретов.
