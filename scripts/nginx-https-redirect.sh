#!/usr/bin/env bash
# Добавляет редирект HTTP → HTTPS в nginx (для видеозвонков в браузере).
# Запускать на сервере: sudo bash scripts/nginx-https-redirect.sh

set -e
CONF="${NGINX_SITE:-/etc/nginx/sites-available/messenger}"

if grep -q 'return 301 https://' "$CONF" 2>/dev/null; then
  echo "Редирект уже есть в $CONF"
  exit 0
fi

DOMAIN=$(grep -m1 server_name "$CONF" | sed -E 's/.*server_name[[:space:]]+([^;]+);.*/\1/' | tr -d ' ')
[ -z "$DOMAIN" ] && { echo "Не найден server_name в $CONF"; exit 1; }

BLOCK=$(cat <<EOF
# Редирект HTTP → HTTPS (звонки в браузере только по HTTPS)
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

EOF
)
sudo cp -a "$CONF" "${CONF}.bak"
{ echo "$BLOCK"; sudo cat "$CONF"; } | sudo tee "$CONF" > /dev/null
sudo nginx -t && sudo systemctl reload nginx
echo "Готово: редирект HTTP → HTTPS добавлен для $DOMAIN"
