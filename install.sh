#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${BUNDLE_DIR}/config/harbor.env"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root: sudo ./install.sh" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

export BUNDLE_DIR ENV_FILE
export HARBOR_HOSTNAME HARBOR_SHORTNAME HARBOR_HTTP_PORT HARBOR_HTTPS_PORT HARBOR_VERSION HARBOR_CONFIG_VERSION
export DHI_HARBOR_PORTAL_IMAGE LOAD_EXTRA_IMAGES USE_DHI_HARBOR_PORTAL
export HARBOR_DATA_VOLUME PREPARE_DATA_DISK DATA_DISK_DEVICE DATA_DISK_LABEL DATA_DISK_FS FORMAT_DATA_DISK MOUNT_DATA_DISK
export HARBOR_LOG_DIR HARBOR_INSTALL_PARENT HARBOR_INSTALL_DIR
export HARBOR_LEAF_CERT_SOURCE HARBOR_LEAF_KEY_SOURCE HARBOR_CA_CERT_SOURCE HARBOR_CA_KEY_SOURCE
export HARBOR_CERT_DIR HARBOR_CERT_DEST HARBOR_KEY_DEST HARBOR_CA_CERT_DEST
export HARBOR_ADMIN_PASSWORD HARBOR_DB_PASSWORD INSTALL_TRIVY INSTALL_DOCKER ALLOW_UNDERSIZED_LAB CONFIGURE_UFW DOCKER_LOG_MAX_SIZE DOCKER_LOG_MAX_FILE

"${BUNDLE_DIR}/scripts/00-prepare-data-disk.sh"
"${BUNDLE_DIR}/scripts/01-preflight.sh"

if [[ "${INSTALL_DOCKER}" == "true" ]]; then
  "${BUNDLE_DIR}/scripts/02-install-docker-offline.sh"
else
  echo "INFO: INSTALL_DOCKER=false; validating existing Docker runtime only."
  docker version >/dev/null
  docker compose version >/dev/null
  if ! command -v docker-compose >/dev/null 2>&1; then
    cat > /usr/local/bin/docker-compose <<'EOF_WRAPPER'
#!/usr/bin/env bash
exec docker compose "$@"
EOF_WRAPPER
    chmod 0755 /usr/local/bin/docker-compose
  fi
fi

"${BUNDLE_DIR}/scripts/03-load-extra-images.sh"
"${BUNDLE_DIR}/scripts/04-stage-harbor-offline-installer.sh"
"${BUNDLE_DIR}/scripts/05-render-harbor-yml.sh"
"${BUNDLE_DIR}/scripts/06-install-harbor.sh"
"${BUNDLE_DIR}/scripts/07-optional-use-dhi-portal.sh"
"${BUNDLE_DIR}/scripts/10-verify.sh"

echo
echo "SUCCESS: Harbor deployment flow completed for ${HARBOR_HOSTNAME}."
echo "Next: import the CA to Docker/containerd clients and browse to https://${HARBOR_HOSTNAME}/"
