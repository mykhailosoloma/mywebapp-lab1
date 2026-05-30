#!/usr/bin/env bash

set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "Запустіть від root: sudo bash setup-runner.sh"; exit 1; }

RUNNER_VERSION="2.317.0"
RUNNER_DIR="/opt/actions-runner"
RUNNER_USER="runner"

echo "1. Системні пакети"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
apt-get install -y -q \
    curl ca-certificates git jq \
    libicu-dev libssl-dev \
    openssh-client

echo "2. Docker (для взаємодії з GHCR)"
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -y -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io
fi
systemctl enable --now docker

echo "3. Користувач runner"
if ! id "${RUNNER_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${RUNNER_USER}"
fi
usermod -aG docker "${RUNNER_USER}"

echo "4. Завантаження GitHub Actions runner v${RUNNER_VERSION}"
mkdir -p "${RUNNER_DIR}"
chown "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"

ARCH="x64"
RUNNER_PKG="actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"

if [ ! -f "${RUNNER_DIR}/config.sh" ]; then
    sudo -u "${RUNNER_USER}" bash -c "
        cd ${RUNNER_DIR}
        curl -fsSL \
            https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_PKG} \
            -o runner.tar.gz
        tar xzf runner.tar.gz
        rm runner.tar.gz
    "
fi

echo "5. Генерація SSH-ключа для доступу до target node"
SSH_KEY_FILE="/home/${RUNNER_USER}/.ssh/id_ed25519_deploy"
if [ ! -f "${SSH_KEY_FILE}" ]; then
    sudo -u "${RUNNER_USER}" bash -c "
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t ed25519 -f ${SSH_KEY_FILE} -N '' -C 'github-runner-deploy'
    "
fi
