#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  echo 'Запусти установку командой sudo bash scripts/install-docker-debian.sh' >&2
  exit 1
fi

source /etc/os-release
if [[ $ID != debian || ${VERSION_CODENAME:-} != trixie ]]; then
  echo 'Этот сценарий рассчитан на Debian 13 (trixie).' >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git python3
install -m 0755 -d /etc/apt/keyrings
curl -fsSL --retry 3 https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker --version
docker compose version
