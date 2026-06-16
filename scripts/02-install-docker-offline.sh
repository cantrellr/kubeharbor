#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Docker Engine and Docker Compose plugin from local .deb files"

DEB_DIR="${BUNDLE_DIR}/packages/docker-debs"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/data/docker}"
CONTAINERD_ROOT="${CONTAINERD_ROOT:-/data/containerd}"
CONFIGURE_CONTAINERD_ROOT="${CONFIGURE_CONTAINERD_ROOT:-true}"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

shopt -s nullglob
debs=("${DEB_DIR}"/*.deb)
if (( ${#debs[@]} == 0 )); then
  fail "no .deb files found in ${DEB_DIR}"
fi

if [[ -z "${DOCKER_DATA_ROOT}" || "${DOCKER_DATA_ROOT}" == "/" ]]; then
  fail "DOCKER_DATA_ROOT is unsafe: ${DOCKER_DATA_ROOT}"
fi
if [[ -z "${CONTAINERD_ROOT}" || "${CONTAINERD_ROOT}" == "/" ]]; then
  fail "CONTAINERD_ROOT is unsafe: ${CONTAINERD_ROOT}"
fi

if [[ -n "${HARBOR_DATA_VOLUME:-}" ]]; then
  if ! findmnt -rn "${HARBOR_DATA_VOLUME}" >/dev/null 2>&1; then
    fail "${HARBOR_DATA_VOLUME} is not mounted. Refusing to place Docker data before /data is ready."
  fi
  case "${DOCKER_DATA_ROOT}" in
    "${HARBOR_DATA_VOLUME}"/*) ;;
    *) warn "DOCKER_DATA_ROOT=${DOCKER_DATA_ROOT} is not under HARBOR_DATA_VOLUME=${HARBOR_DATA_VOLUME}. This may consume OS disk." ;;
  esac
  case "${CONTAINERD_ROOT}" in
    "${HARBOR_DATA_VOLUME}"/*) ;;
    *) warn "CONTAINERD_ROOT=${CONTAINERD_ROOT} is not under HARBOR_DATA_VOLUME=${HARBOR_DATA_VOLUME}. This may consume OS disk." ;;
  esac
fi

install -d -m 0755 "${DOCKER_DATA_ROOT}" "${CONTAINERD_ROOT}"

# Docker Engine keeps daemon configuration here on Linux. Keep Harbor networking intact.
install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<EOF_DAEMON
{
  "data-root": "${DOCKER_DATA_ROOT}",
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

# Docker Engine 29+ fresh installs may use the containerd image store. In that mode,
# image content can live under containerd's root, not only Docker's data-root. Put both
# under /data so the 64 GB OS disk does not become the image cache.
if [[ "${CONFIGURE_CONTAINERD_ROOT}" == "true" ]]; then
  install -d -m 0755 /etc/containerd
  if [[ -f /etc/containerd/config.toml && ! -f /etc/containerd/config.toml.kubeharbor.bak ]]; then
    cp -a /etc/containerd/config.toml /etc/containerd/config.toml.kubeharbor.bak
  fi
  cat > /etc/containerd/config.toml <<EOF_CONTAINERD
version = 2
root = "${CONTAINERD_ROOT}"
state = "/run/containerd"
EOF_CONTAINERD
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends "${debs[@]}"

systemctl daemon-reload
systemctl restart containerd || true
systemctl enable --now docker
systemctl restart docker

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

echo "INFO: Docker root dir: $(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo unknown)"
echo "INFO: Expected Docker data-root: ${DOCKER_DATA_ROOT}"
echo "INFO: Expected containerd root: ${CONTAINERD_ROOT}"
echo "INFO: Docker runtime installed and running."
