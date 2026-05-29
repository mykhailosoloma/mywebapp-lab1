#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_USER="app"
APP_DIR="/opt/mywebapp"
CONFIG_DIR="/etc/mywebapp"
DB_NAME="mywebapp"
DB_USER="mywebapp"
DB_PASS="$(openssl rand -hex 16)"

[ "$EUID" -eq 0 ] || { echo "Запустіть від root: sudo bash deploy.sh"; exit 1; }

echo "==> 1. Встановлення пакетів"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
apt-get install -y -q openjdk-21-jdk-headless postgresql nginx curl openssl python3-yaml

echo "==> 2. Створення користувачів"
for user in student teacher; do
    if ! id "$user" &>/dev/null; then
        useradd -m -s /bin/bash "$user"
        echo "$user:12345678" | chpasswd
        usermod -aG sudo "$user"
        passwd -e "$user"
    fi
done

if ! id "$APP_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$APP_DIR" -G www-data "$APP_USER"
fi

if ! id operator &>/dev/null; then
    useradd -m -s /bin/bash operator 2>/dev/null || useradd -m -s /bin/bash -g operator operator
    echo "operator:12345678" | chpasswd
    passwd -e operator
fi

cat > /etc/sudoers.d/operator << 'SUDOERS'
operator ALL=(root) NOPASSWD: /usr/bin/systemctl start mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl stop mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl restart mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl status mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
SUDOERS
chmod 0440 /etc/sudoers.d/operator

echo "==> 3. Налаштування PostgreSQL"
systemctl enable --now postgresql
until pg_isready -q; do sleep 1; done

sudo -u postgres psql -v ON_ERROR_STOP=1 << PSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  ELSE
    ALTER ROLE ${DB_USER} PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')
\gexec
PSQL

PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)
grep -q "^host ${DB_NAME} ${DB_USER}" "$PG_HBA" || \
    echo "host ${DB_NAME} ${DB_USER} 127.0.0.1/32 md5" >> "$PG_HBA"
systemctl reload postgresql

echo "==> 4. Розгортання файлів застосунку"
mkdir -p "$APP_DIR"
cp "${SCRIPT_DIR}/mywebapp.jar"   "$APP_DIR/"
cp "${SCRIPT_DIR}/migration.sql"  "$APP_DIR/"
cp "${SCRIPT_DIR}/migrate.sh"     "$APP_DIR/"
chmod +x "$APP_DIR/migrate.sh"
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR"

echo "==> 5. Конфігурація застосунку"
mkdir -p "$CONFIG_DIR"
cat > "${CONFIG_DIR}/config.yml" << CONF
app:
  server:
    host: 127.0.0.1
    port: 8080
  database:
    host: 127.0.0.1
    port: 5432
    name: ${DB_NAME}
    user: ${DB_USER}
    password: ${DB_PASS}
CONF
chmod 640 "${CONFIG_DIR}/config.yml"
chown root:"${APP_USER}" "${CONFIG_DIR}/config.yml"

echo "==> 6. systemd (socket activation)"
cp "${SCRIPT_DIR}/mywebapp.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/mywebapp.socket"  /etc/systemd/system/
systemctl daemon-reload
systemctl enable mywebapp.socket mywebapp.service
systemctl start mywebapp.socket
systemctl start mywebapp.service

echo "==> 7. Nginx"
systemctl enable nginx
cp "${SCRIPT_DIR}/nginx-mywebapp.conf" /etc/nginx/sites-available/mywebapp
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
nginx -t && systemctl restart nginx

echo "25" > /home/student/gradebook
chown student:student /home/student/gradebook

echo "==> 9. Блокування дефолтного користувача"
if id ubuntu &>/dev/null; then
    passwd -l ubuntu
    usermod -s /usr/sbin/nologin ubuntu
fi

echo ""
echo "Перевірка: curl http://127.0.0.1/"
echo "==> Перевірка стану сервісів"
sleep 3
systemctl is-active mywebapp.socket && echo "  mywebapp.socket: OK" || echo "  mywebapp.socket: FAILED"
systemctl is-active mywebapp.service && echo "  mywebapp.service: OK" || echo "  mywebapp.service: FAILED"
systemctl is-active nginx && echo "  nginx: OK" || echo "  nginx: FAILED"