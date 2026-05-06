#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-/etc/mywebapp/config.yml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

parse_yaml_value() {
    local key="$1"
    grep -E "^\s*${key}:" "$CONFIG_FILE" | head -1 | sed 's/.*: *//' | tr -d '"\047' | xargs
}

if [ -f "$CONFIG_FILE" ]; then
    DB_HOST=$(parse_yaml_value "host" 2>/dev/null || echo "127.0.0.1")
    DB_PORT=$(parse_yaml_value "port" 2>/dev/null || echo "5432")
    DB_NAME=$(parse_yaml_value "name" 2>/dev/null || echo "mywebapp")
    DB_USER=$(parse_yaml_value "user" 2>/dev/null || echo "mywebapp")
    DB_PASS=$(parse_yaml_value "password" 2>/dev/null || echo "mywebapp")

    if command -v python3 &>/dev/null; then
        DB_HOST=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    db = c.get('app', {}).get('database', {})
    print(db.get('host', '127.0.0.1'))
except: print('127.0.0.1')
" 2>/dev/null)
        DB_PORT=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    db = c.get('app', {}).get('database', {})
    print(db.get('port', 5432))
except: print('5432')
" 2>/dev/null)
        DB_NAME=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    db = c.get('app', {}).get('database', {})
    print(db.get('name', 'mywebapp'))
except: print('mywebapp')
" 2>/dev/null)
        DB_USER=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    db = c.get('app', {}).get('database', {})
    print(db.get('user', 'mywebapp'))
except: print('mywebapp')
" 2>/dev/null)
        DB_PASS=$(python3 -c "
import sys
try:
    import yaml
    with open('$CONFIG_FILE') as f:
        c = yaml.safe_load(f)
    db = c.get('app', {}).get('database', {})
    print(db.get('password', 'mywebapp'))
except: print('mywebapp')
" 2>/dev/null)
    fi
else
    echo "Config file not found: $CONFIG_FILE, using defaults"
    DB_HOST="127.0.0.1"
    DB_PORT="5432"
    DB_NAME="mywebapp"
    DB_USER="mywebapp"
    DB_PASS="mywebapp"
fi

SQL_FILE="${SCRIPT_DIR}/migration.sql"
if [ ! -f "$SQL_FILE" ]; then
    SQL_FILE="/opt/mywebapp/migration.sql"
fi

echo "Running migration on ${DB_HOST}:${DB_PORT}/${DB_NAME} ..."
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE"
echo "Migration completed successfully."
