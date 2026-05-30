#!/usr/bin/env bash

set -euo pipefail

APP_DIR="/opt/mywebapp"
SERVICE_NAME="mywebapp"

echo "==> Pulling image: ${IMAGE}"
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin

docker pull "${IMAGE}"

echo "==> Updating image reference"
echo "${IMAGE}" | sudo tee "${APP_DIR}/current-image"

echo "==> Restarting service"
sudo systemctl restart "${SERVICE_NAME}"

echo "==> Waiting for service to become healthy (up to 60s)"
for i in $(seq 1 12); do
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        sleep 5
        if curl -sf http://127.0.0.1/health/alive >/dev/null 2>&1; then
            echo "==> Service is up after $((i * 5))s"
            exit 0
        fi
    fi
    echo "   Waiting... attempt ${i}/12"
    sleep 5
done

echo "ERROR: Service did not become healthy in time"
sudo systemctl status "${SERVICE_NAME}" || true
exit 1