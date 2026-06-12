#!/usr/bin/env bash
set -euo pipefail

echo "==> Verifying Harbor"

cd "${HARBOR_INSTALL_DIR}"
docker compose ps

if docker image inspect "${DHI_HARBOR_PORTAL_IMAGE}" >/dev/null 2>&1; then
  echo "INFO: DHI portal image is loaded: ${DHI_HARBOR_PORTAL_IMAGE}"
fi

if [[ "${USE_DHI_HARBOR_PORTAL}" == "true" ]]; then
  if docker compose ps portal | grep -q "portal"; then
    echo "INFO: portal service is present. Confirm image with: docker compose images portal"
  fi
fi

# /api/v2.0/ping returns a simple response when API is up.
if command -v curl >/dev/null 2>&1; then
  echo "INFO: checking Harbor API ping over HTTPS..."
  curl -kfsS "https://${HARBOR_HOSTNAME}:${HARBOR_HTTPS_PORT}/api/v2.0/ping" || {
    echo "WARN: Harbor API ping failed. Check docker compose ps and /var/log/harbor/." >&2
  }
else
  echo "WARN: curl not installed; skipping HTTPS API ping."
fi

echo "INFO: verification complete."
