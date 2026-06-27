#!/usr/bin/env bash
set -euo pipefail

# Basic filesystem backup helper. For production, integrate with your enterprise backup stack.
# Usage: sudo ./scripts/09-backup-harbor.sh [/backup]

BACKUP_ROOT="${1:-/backup}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/harbor-${STAMP}"

# Source env file if available so HARBOR_INSTALL_DIR and HARBOR_DATA_VOLUME are respected.
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${BUNDLE_DIR}/config/harbor.env" ]]; then
  # shellcheck disable=SC1091
  source "${BUNDLE_DIR}/config/harbor.env"
fi
HARBOR_INSTALL_DIR="${HARBOR_INSTALL_DIR:-/opt/harbor}"
HARBOR_DATA_VOLUME="${HARBOR_DATA_VOLUME:-/data}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

if [[ -d "${HARBOR_INSTALL_DIR}" ]]; then
  docker compose -f "${HARBOR_INSTALL_DIR}/docker-compose.yml" down
fi

data_rel="${HARBOR_DATA_VOLUME#/}"
tar -C / -czf "${BACKUP_DIR}/harbor-data.tgz" "${data_rel}" || true
tar -C / -czf "${BACKUP_DIR}/harbor-config.tgz" "${HARBOR_INSTALL_DIR#/}" etc/docker/daemon.json || true
tar -C / -czf "${BACKUP_DIR}/harbor-logs.tgz" var/log/harbor || true

if [[ -d "${HARBOR_INSTALL_DIR}" ]]; then
  docker compose -f "${HARBOR_INSTALL_DIR}/docker-compose.yml" up -d
fi

echo "Backup written to ${BACKUP_DIR}"
