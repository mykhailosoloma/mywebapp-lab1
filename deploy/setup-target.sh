#!/usr/bin/env bash

set -euo pipefail

APP_DIR="/opt/mywebapp"
NGINX_CONF="/etc/nginx/sites-available/mywebapp"
SERVICE_FILE="/etc/systemd/system/mywebapp.service"
NETWORK_NAME="mywebapp-net"
DB_NAME="mywebapp"
DB_USER="mywebapp"
DB_PASS="$(openssl rand -hex 16)"

[ "$EUID" -eq 0 ] || { echo "Запустіть від root: sudo bash setup-target.sh"; exit 1; }

echo "1. Встановлення пакетів"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
apt-get install -y -q curl ca-certificates nginx openssl

if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/ubuntu \
        # shellcheck source=/dev/null
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -y -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io
fi

systemctl enable --now docker

echo "2. Створення Docker-мережі"
docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 \
    || docker network create "${NETWORK_NAME}"

echo "3. Запуск PostgreSQL у контейнері"
if ! docker ps -a --format '{{.Names}}' | grep -q '^mywebapp-db$'; then
    docker run -d \
        --name mywebapp-db \
        --network "${NETWORK_NAME}" \
        --restart unless-stopped \
        -e POSTGRES_DB="${DB_NAME}" \
        -e POSTGRES_USER="${DB_USER}" \
        -e POSTGRES_PASSWORD="${DB_PASS}" \
        -v mywebapp-pgdata:/var/lib/postgresql/data \
        postgres:16-alpine

    for _ in $(seq 1 20); do
        docker exec mywebapp-db pg_isready -U "${DB_USER}" -d "${DB_NAME}" \
            >/dev/null 2>&1 && break
        sleep 3
    done
else
    echo " PostgreSQL контейнер вже існує, пропускаємо"
    if [ -f "${APP_DIR}/mywebapp.env" ]; then
        DB_PASS=$(grep SPRING_DATASOURCE_PASSWORD "${APP_DIR}/mywebapp.env" \
            | cut -d= -f2)
    fi
fi

echo "4. Застосування міграцій БД"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker cp "${SCRIPT_DIR}/migration.sql" mywebapp-db:/tmp/migration.sql
docker exec mywebapp-db psql -U "${DB_USER}" -d "${DB_NAME}" \
    -f /tmp/migration.sql

echo "5. Підготовка директорій і конфігурацій"
mkdir -p "${APP_DIR}"

cat > "${APP_DIR}/mywebapp.env" <<ENV
SPRING_DATASOURCE_URL=jdbc:postgresql://mywebapp-db:5432/${DB_NAME}
SPRING_DATASOURCE_USERNAME=${DB_USER}
SPRING_DATASOURCE_PASSWORD=${DB_PASS}
SERVER_ADDRESS=0.0.0.0
SERVER_PORT=8080
ENV
chmod 640 "${APP_DIR}/mywebapp.env"

[ -f "${APP_DIR}/current-image" ] \
    || echo "ghcr.io/placeholder/mywebapp:latest" > "${APP_DIR}/current-image"

cp "${SCRIPT_DIR}/verify.sh" "${APP_DIR}/verify.sh"
chmod +x "${APP_DIR}/verify.sh"

echo "6. Systemd unit"
cp "${SCRIPT_DIR}/mywebapp-container.service" "${SERVICE_FILE}"
systemctl daemon-reload
systemctl enable mywebapp

echo "7. Налаштування nginx"
cp "${SCRIPT_DIR}/nginx-mywebapp.conf" "${NGINX_CONF}"
rm -f /etc/nginx/sites-enabled/default
ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/mywebapp
nginx -t
systemctl enable --now nginx

echo "8. Користувач operator (для розгортання з раннера)"
if ! id operator &>/dev/null; then
    useradd -m -s /bin/bash operator
fi

cat > /etc/sudoers.d/operator-deploy <<'SUDOERS'
operator ALL=(root) NOPASSWD: /usr/bin/systemctl start mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl stop mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl restart mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl status mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/tee /opt/mywebapp/current-image
SUDOERS
chmod 0440 /etc/sudoers.d/operator-deploy

usermod -aG docker operator 2>/dev/null || true
