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

echo "==> Waiting for container to start (up to 90s)"
for i in $(seq 1 18); do
    if docker ps --format '{{.Names}}' | grep -q '^mywebapp$'; then
        # Отримуємо IP контейнера в Docker мережі
        CONTAINER_IP=$(docker inspect mywebapp \
            --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
        if [ -n "${CONTAINER_IP}" ]; then
            if curl -sf "http://${CONTAINER_IP}:8080/health/alive" >/dev/null 2>&1; then
                echo "==> Service is up after $((i * 5))s"
                exit 0
            fi
        fi
    fi
    echo "   Waiting... attempt ${i}/18"
    sleep 5
done

echo "ERROR: Service did not become healthy in time"
sudo systemctl status "${SERVICE_NAME}" || true
exit 1
