#!/usr/bin/env bash

set -uo pipefail

PASS=0
FAIL=0
BASE_URL="http://127.0.0.1"


ok()   { echo "  $*"; PASS=$((PASS + 1)); }
fail() { echo "  $*"; FAIL=$((FAIL + 1)); }
section() { echo ""; echo "── $* ──────────────────────────────────────"; }


section "systemd service"
if systemctl is-active --quiet mywebapp; then
    ok "mywebapp.service is active"
else
    fail "mywebapp.service is NOT active"
    systemctl status mywebapp --no-pager -l || true
fi

section "Docker container"
if docker ps --format '{{.Names}}' | grep -q '^mywebapp$'; then
    ok "mywebapp container is running"
else
    fail "mywebapp container is NOT running"
fi

if docker ps --format '{{.Names}}' | grep -q '^mywebapp-db$'; then
    ok "mywebapp-db container is running"
else
    fail "mywebapp-db container is NOT running"
fi

section "nginx"
if systemctl is-active --quiet nginx; then
    ok "nginx is active"
else
    fail "nginx is NOT active"
fi

if nginx -t 2>/dev/null; then
    ok "nginx config is valid"
else
    fail "nginx config is INVALID"
    nginx -t 2>&1 || true
fi

if ss -tlnp | grep -q ':80 '; then
    ok "nginx listening on :80"
else
    fail "nothing listening on :80"
fi

section "HTTP availability"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 "${BASE_URL}/")
if [ "$HTTP_STATUS" = "200" ]; then
    ok "GET / returns 200"
else
    fail "GET / returned ${HTTP_STATUS} (expected 200)"
fi

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 "${BASE_URL}/health/alive")
if [ "$HEALTH_STATUS" = "200" ]; then
    ok "GET /health/alive returns 200"
else
    fail "GET /health/alive returned ${HEALTH_STATUS} (expected 200)"
fi

NOT_FOUND_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 "${BASE_URL}/unknown-path")
if [ "$NOT_FOUND_STATUS" = "404" ]; then
    ok "GET /unknown-path returns 404 (nginx catch-all works)"
else
    fail "GET /unknown-path returned ${NOT_FOUND_STATUS} (expected 404)"
fi

section "nginx proxy headers"

if grep -q "proxy_set_header.*X-Real-IP" /etc/nginx/sites-enabled/mywebapp 2>/dev/null \
   || grep -rq "proxy_set_header.*X-Real-IP" /etc/nginx/sites-available/mywebapp 2>/dev/null; then
    ok "nginx sets X-Real-IP header"
else
    fail "nginx does NOT set X-Real-IP header"
fi

if grep -q "proxy_set_header.*X-Forwarded-For" /etc/nginx/sites-enabled/mywebapp 2>/dev/null \
   || grep -rq "proxy_set_header.*X-Forwarded-For" /etc/nginx/sites-available/mywebapp 2>/dev/null; then
    ok "nginx sets X-Forwarded-For header"
else
    fail "nginx does NOT set X-Forwarded-For header"
fi

section "API /tasks endpoint"

TASKS_RESPONSE=$(curl -s --max-time 10 \
    -H "Accept: application/json" "${BASE_URL}/tasks")
TASKS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 -H "Accept: application/json" "${BASE_URL}/tasks")

if [ "$TASKS_STATUS" = "200" ]; then
    ok "GET /tasks returns 200"
else
    fail "GET /tasks returned ${TASKS_STATUS} (expected 200)"
fi

if echo "$TASKS_RESPONSE" | grep -qE '^\['; then
    ok "GET /tasks returns JSON array"
else
    fail "GET /tasks did not return JSON array (got: ${TASKS_RESPONSE:0:100})"
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0