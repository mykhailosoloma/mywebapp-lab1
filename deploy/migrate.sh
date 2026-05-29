#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-/etc/mywebapp/config.yml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/migration.sql"

[ -f "$CONFIG_FILE" ] || { echo "Конфіг не знайдено: $CONFIG_FILE"; exit 1; }

PARSE_PY=$(mktemp /tmp/parse_config.XXXXXX.py)
trap 'rm -f "$PARSE_PY"' EXIT

cat > "$PARSE_PY" << 'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    c = yaml.safe_load(f)
db = c["app"]["database"]
print(db["host"])
print(db["port"])
print(db["name"])
print(db["user"])
print(db["password"])
PYEOF

DB_HOST=$(python3 "$PARSE_PY" "$CONFIG_FILE" | sed -n '1p')
DB_PORT=$(python3 "$PARSE_PY" "$CONFIG_FILE" | sed -n '2p')
DB_NAME=$(python3 "$PARSE_PY" "$CONFIG_FILE" | sed -n '3p')
DB_USER=$(python3 "$PARSE_PY" "$CONFIG_FILE" | sed -n '4p')
DB_PASS=$(python3 "$PARSE_PY" "$CONFIG_FILE" | sed -n '5p')

echo "Міграція: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE"
echo "Міграція виконана успішно."