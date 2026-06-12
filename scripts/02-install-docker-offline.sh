#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Docker Engine and Docker Compose plugin from local .deb files"

DEB_DIR="${BUNDLE_DIR}/packages/docker-debs"
shopt -s nullglob
debs=("${DEB_DIR}"/*.deb)
if (( ${#debs[@]} == 0 )); then
  echo "ERROR: no .deb files found in ${DEB_DIR}" >&2
  exit 1
fi

# Create a conservative daemon config. Do not disable iptables; Harbor depends on Docker networking.
install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<EOF_DAEMON
{
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILE}"
  }
}
EOF_DAEMON

export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends "${debs[@]}"

systemctl enable --now docker

# Some Harbor installer versions still call docker-compose. Provide a compatibility wrapper
# backed by the Docker Compose v2 plugin when the legacy binary is absent.
if ! command -v docker-compose >/dev/null 2>&1; then
  cat > /usr/local/bin/docker-compose <<'EOF_WRAPPER'
#!/usr/bin/env bash
exec docker compose "$@"
EOF_WRAPPER
  chmod 0755 /usr/local/bin/docker-compose
fi

docker version
docker compose version
docker-compose version

echo "INFO: Docker runtime installed and running."
