#!/usr/bin/env bash
set -euo pipefail

HARBOR_DIR="${HARBOR_DIR:-/opt/harbor}"

if [[ ! -d "${HARBOR_DIR}" ]]; then
  echo "ERROR: Harbor directory not found: ${HARBOR_DIR}" >&2
  exit 1
fi

cd "${HARBOR_DIR}"

echo "INFO: starting Harbor services with serial log bootstrap"
docker compose up -d log

log_ready="false"
for _ in {1..20}; do
  if ss -ltn '( sport = :1514 )' 2>/dev/null | grep -q ':1514'; then
    log_ready="true"
    break
  fi
  sleep 1
done

if [[ "${log_ready}" != "true" ]]; then
  echo "ERROR: harbor-log listener on 127.0.0.1:1514 did not become ready." >&2
  exit 1
fi

docker compose up -d
echo "INFO: Harbor serial startup complete."