#!/usr/bin/env bash

set -euo pipefail

REPO_URL=""
APP_DIR="/opt/mywebapp"
CONFIG_DIR="/etc/mywebapp"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
DB_NAME="mywebapp"
DB_USER="mywebapp"
DB_PASS="$(openssl rand -base64 16)"
GRADEBOOK_N=25
APP_USER="mywebapp"

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_root() {
    [ "$EUID" -eq 0 ] || die "Run this script as root (sudo bash deploy.sh)"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_packages() {
    log "Installing packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
        openjdk-21-jdk-headless \
        maven \
        postgresql \
        nginx \
        git \
        curl \
        openssl \
        python3 \
        python3-yaml \
        postgresql-client
}

create_users() {
    log "Creating users"

    if ! id student &>/dev/null; then
        useradd -m -s /bin/bash -c "Student user" student
        echo "student:12345678" | chpasswd
        usermod -aG sudo student
        passwd -e student
        log "Created user: student"
    fi

    if ! id teacher &>/dev/null; then
        useradd -m -s /bin/bash -c "Teacher user" teacher
        echo "teacher:12345678" | chpasswd
        usermod -aG sudo teacher
        passwd -e teacher
        log "Created user: teacher"
    fi

    if ! id "${APP_USER}" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin -d /opt/mywebapp -c "mywebapp service account" "${APP_USER}"
        log "Created system user: ${APP_USER}"
    fi

    if ! id operator &>/dev/null; then
        if getent group operator &>/dev/null; then
            useradd -m -s /bin/bash -c "Operator user" \
                    -g operator \
                    --no-user-group \
                    operator
        else
            useradd -m -s /bin/bash -c "Operator user" operator
        fi
        echo "operator:12345678" | chpasswd
        passwd -e operator
        log "Created user: operator"
    fi

    cat > /etc/sudoers.d/operator << 'SUDOERS'
operator ALL=(root) NOPASSWD: /usr/bin/systemctl start mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl stop mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl restart mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl status mywebapp
operator ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
SUDOERS
    chmod 0440 /etc/sudoers.d/operator
    log "Configured sudoers for operator"
}

setup_database() {
    log "Setting up PostgreSQL"
    systemctl enable postgresql
    systemctl start postgresql

    local retries=15
    until pg_isready -q 2>/dev/null; do
        retries=$((retries - 1))
        [ $retries -le 0 ] && die "PostgreSQL did not start in time"
        sleep 1
    done

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

    local pg_conf
    pg_conf=$(find /etc/postgresql -name postgresql.conf | head -1)
    if [ -n "$pg_conf" ]; then
        sed -i "s/^#*listen_addresses\s*=.*/listen_addresses = '127.0.0.1'/" "$pg_conf"
        local hba
        hba=$(find /etc/postgresql -name pg_hba.conf | head -1)
        if ! grep -q "${DB_USER}" "$hba" 2>/dev/null; then
            echo "host ${DB_NAME} ${DB_USER} 127.0.0.1/32 md5" >> "$hba"
        fi
        systemctl reload postgresql || systemctl restart postgresql
    fi

    log "PostgreSQL configured. DB=${DB_NAME} USER=${DB_USER}"
}

build_or_find_jar() {
    log "Locating application JAR"

    JAR_PATH=""

    if [ -n "${REPO_URL}" ]; then
        log "Cloning and building from ${REPO_URL} ..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        git clone "$REPO_URL" "$tmp_dir/src"
        pushd "$tmp_dir/src" > /dev/null
        ./mvnw -q package -DskipTests
        JAR_PATH="$tmp_dir/src/target/mywebapp.jar"
        MIGRATION_SQL="$tmp_dir/src/src/main/resources/migration.sql"
        MIGRATE_SH="$tmp_dir/src/deploy/migrate.sh"
        popd > /dev/null
        return
    fi

    if [ -f "${SCRIPT_DIR}/mywebapp.jar" ]; then
        JAR_PATH="${SCRIPT_DIR}/mywebapp.jar"
    else
        die "Cannot find mywebapp.jar. Place it next to deploy.sh or set REPO_URL."
    fi

    if [ -f "${SCRIPT_DIR}/migration.sql" ]; then
        MIGRATION_SQL="${SCRIPT_DIR}/migration.sql"
    else
        die "Cannot find migration.sql next to deploy.sh"
    fi

    if [ -f "${SCRIPT_DIR}/migrate.sh" ]; then
        MIGRATE_SH="${SCRIPT_DIR}/migrate.sh"
    else
        die "Cannot find migrate.sh next to deploy.sh"
    fi
}

deploy_app() {
    log "Deploying application files"
    mkdir -p "${APP_DIR}"

    cp "${JAR_PATH}"       "${APP_DIR}/mywebapp.jar"
    cp "${MIGRATION_SQL}"  "${APP_DIR}/migration.sql"
    cp "${MIGRATE_SH}"     "${APP_DIR}/migrate.sh"
    chmod +x "${APP_DIR}/migrate.sh"

    chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
    log "Files deployed to ${APP_DIR}"
}

create_config() {
    log "Creating application config"
    mkdir -p "${CONFIG_DIR}"

    cat > "${CONFIG_FILE}" << CONFEOF
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
CONFEOF

    chmod 640 "${CONFIG_FILE}"
    chown root:"${APP_USER}" "${CONFIG_FILE}"
    log "Config written to ${CONFIG_FILE}"
}

run_migration() {
    log "Running database migration"
    sudo -u "${APP_USER}" bash "${APP_DIR}/migrate.sh" "${CONFIG_FILE}"
}

setup_systemd() {
    log "Setting up systemd service"

    cat > /etc/systemd/system/mywebapp.service << SVCEOF
[Unit]
Description=mywebapp Task Tracker Web Application
After=network.target postgresql.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=/opt/mywebapp
ExecStartPre=/opt/mywebapp/migrate.sh /etc/mywebapp/config.yml
ExecStart=/usr/bin/java -jar /opt/mywebapp/mywebapp.jar
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mywebapp
Environment="JAVA_OPTS=-Xms128m -Xmx256m"
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=/opt/mywebapp /tmp

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable mywebapp.service
    log "systemd service installed and enabled"
}

start_service() {
    log "Starting mywebapp"
    systemctl start mywebapp

    local retries=30
    log "Waiting for application to become ready..."
    until curl -sf http://127.0.0.1:8080/health/alive > /dev/null 2>&1; do
        retries=$((retries - 1))
        if [ $retries -le 0 ]; then
            warn "Application did not respond in time. Check logs: journalctl -u mywebapp -n 50"
            break
        fi
        sleep 2
    done
    log "mywebapp is running"
}

setup_nginx() {
    log "Configuring Nginx"
    systemctl enable nginx

    cat > /etc/nginx/sites-available/mywebapp << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/mywebapp_access.log combined;
    error_log  /var/log/nginx/mywebapp_error.log warn;

    location = / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }

    location /tasks {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }

    location / {
        return 404;
    }
}
NGINXEOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp

    nginx -t && systemctl restart nginx
    log "Nginx configured and restarted"
}

create_gradebook() {
    log "Creating gradebook"
    echo "${GRADEBOOK_N}" > /home/student/gradebook
    chown student:student /home/student/gradebook
    log "Gradebook: /home/student/gradebook = ${GRADEBOOK_N}"
}

block_default_user() {
    log "Blocking default system user"
    local default_users=("ubuntu" "vagrant" "debian" "centos" "ec2-user" "cloud-user")
    for u in "${default_users[@]}"; do
        if id "$u" &>/dev/null 2>&1; then
            passwd -l "$u"
            usermod -s /usr/sbin/nologin "$u"
            log "Locked user: $u"
        fi
    done
}

main() {
    require_root
    log "Starting deployment"

    install_packages
    create_users
    setup_database
    build_or_find_jar
    deploy_app
    create_config
    run_migration
    setup_systemd
    start_service
    setup_nginx
    create_gradebook
    block_default_user

    log "Deployment complete!"
}

main "$@"