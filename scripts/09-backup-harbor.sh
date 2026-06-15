#!/usr/bin/env bash
set -euo pipefail

# Basic filesystem backup helper. For production, integrate with your enterprise backup stack.
# Usage: sudo ./scripts/09-backup-harbor.sh [/backup]

BACKUP_ROOT="${1:-/backup}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/harbor-${STAMP}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

if [[ -d /opt/harbor ]]; then
  docker compose -f /opt/harbor/docker-compose.yml down
fi

tar -C / -czf "${BACKUP_DIR}/harbor-data.tgz" data || true
tar -C / -czf "${BACKUP_DIR}/harbor-config.tgz" opt/harbor etc/docker/daemon.json || true
tar -C / -czf "${BACKUP_DIR}/harbor-logs.tgz" var/log/harbor || true

if [[ -d /opt/harbor ]]; then
  docker compose -f /opt/harbor/docker-compose.yml up -d
fi

echo "Backup written to ${BACKUP_DIR}"
