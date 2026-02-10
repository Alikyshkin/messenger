#!/usr/bin/env bash
# Запускать на сервере (после ssh). Обновляет код из main и перезапускает приложение.
# Использовать, пока автодеплой из GitHub Actions не настроен.

set -e
DEPLOY_PATH="${DEPLOY_PATH:-/opt/messenger}"
cd "$DEPLOY_PATH"
git fetch origin main
git reset --hard origin/main
cd server
npm ci --omit=dev
mkdir -p public
pm2 restart messenger || (pm2 start index.js --name messenger)
pm2 save
echo "Done. App updated and restarted."
