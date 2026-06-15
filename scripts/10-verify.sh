#!/usr/bin/env bash
set -euo pipefail

echo "==> Verifying Harbor"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

cd "${HARBOR_INSTALL_DIR}"
docker compose ps

required_services=(proxy core portal registry registryctl jobservice postgresql redis log)
if [[ "${INSTALL_TRIVY}" == "true" ]]; then
  required_services+=(trivy)
fi

all_running="false"
for attempt in {1..20}; do
  running_services="$(docker compose ps --status running --services || true)"
  missing=()
  for svc in "${required_services[@]}"; do
    if ! grep -qx "${svc}" <<<"${running_services}"; then
      missing+=("$svc")
    fi
  done
  if (( ${#missing[@]} == 0 )); then
    all_running="true"
    break
  fi
  echo "INFO: waiting for Harbor services to become running (attempt ${attempt}/20): missing ${missing[*]}"
  sleep 3
done

if [[ "$all_running" != "true" ]]; then
  fail "Required Harbor services are not running: ${missing[*]}"
fi
echo "INFO: required Harbor services are running."

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
  api_host="${HARBOR_HOSTNAME}"
  if ! getent hosts "${HARBOR_HOSTNAME}" >/dev/null 2>&1; then
    warn "${HARBOR_HOSTNAME} does not resolve on this host; falling back to 127.0.0.1 for local API checks."
    api_host="127.0.0.1"
  fi

  echo "INFO: checking Harbor API ping over HTTPS with retries..."
  api_ok="false"
  for attempt in {1..10}; do
    if curl -kfsS "https://${api_host}:${HARBOR_HTTPS_PORT}/api/v2.0/ping" >/dev/null; then
      api_ok="true"
      break
    fi
    echo "INFO: API ping attempt ${attempt}/10 failed; retrying..."
    sleep 3
  done
  if [[ "$api_ok" != "true" ]]; then
    warn "Harbor API ping failed after retries. Check docker compose ps and /var/log/harbor/."
  else
    echo "INFO: Harbor API ping succeeded."
  fi

  if [[ "${HARBOR_ADMIN_PASSWORD}" != CHANGE-ME-* && -n "${HARBOR_ADMIN_PASSWORD}" ]]; then
    if curl -kfsS -u "admin:${HARBOR_ADMIN_PASSWORD}" "https://${api_host}:${HARBOR_HTTPS_PORT}/api/v2.0/projects?page=1&page_size=1" >/dev/null; then
      echo "INFO: authenticated Harbor API check succeeded."
    else
      warn "Authenticated API check failed for admin account."
    fi
  fi
else
  warn "curl not installed; skipping HTTPS API ping."
fi

echo "INFO: verification complete."
