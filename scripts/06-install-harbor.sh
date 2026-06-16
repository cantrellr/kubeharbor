#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Harbor"

cd "${HARBOR_INSTALL_DIR}"

if [[ "${CONFIGURE_UFW}" == "true" ]] && command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -qi "Status: active"; then
    ufw allow "${HARBOR_HTTP_PORT}/tcp" || true
    ufw allow "${HARBOR_HTTPS_PORT}/tcp" || true
  fi
fi

args=()
if [[ "${INSTALL_TRIVY}" == "true" ]]; then
  args+=("--with-trivy")
fi

start_harbor_with_serial_log_bootstrap() {
  echo "INFO: applying fallback startup: bootstrap harbor-log first, then start remaining services."

  prepare_args=()
  if [[ "${INSTALL_TRIVY}" == "true" ]]; then
    prepare_args+=("--with-trivy")
  fi

  ./prepare "${prepare_args[@]}"
  docker compose down -v || true
  docker compose up -d log

  log_listener_ready="false"
  for _ in {1..20}; do
    if ss -ltn '( sport = :1514 )' 2>/dev/null | grep -q ':1514'; then
      log_listener_ready="true"
      break
    fi
    sleep 1
  done

  if [[ "${log_listener_ready}" != "true" ]]; then
    echo "ERROR: harbor-log listener on 127.0.0.1:1514 did not become ready during fallback startup." >&2
    return 1
  fi

  docker compose up -d
}

reconcile_db_password_if_needed() {
  # On reruns with existing /data DB state, Harbor can fail if HARBOR_DB_PASSWORD changed.
  if ! docker compose ps core >/dev/null 2>&1; then
    return 0
  fi

  sleep 3
  if ! docker logs --tail=120 harbor-core 2>/dev/null | grep -q 'password authentication failed for user "postgres"'; then
    return 0
  fi

  echo "WARN: detected Harbor DB auth mismatch for user postgres. Attempting one-time credential reconciliation." >&2
  if ! docker exec -i harbor-db psql -U postgres -d postgres -v "dbpass=${HARBOR_DB_PASSWORD}" -c "ALTER USER postgres WITH PASSWORD :'dbpass';" >/dev/null; then
    echo "ERROR: failed to reconcile postgres password inside harbor-db container." >&2
    return 1
  fi

  docker compose restart core jobservice proxy >/dev/null
  echo "INFO: reconciled Harbor DB password and restarted core/jobservice/proxy." >&2
}

# The offline installer includes Harbor's official image tarball. install.sh loads it locally and generates docker-compose.yml.
attempt=1
max_attempts=3
while true; do
  install_log="$(mktemp)"
  if ./install.sh "${args[@]}" 2>&1 | tee "${install_log}"; then
    rm -f "${install_log}"
    break
  fi

  if grep -q "failed to initialize logging driver: dial tcp 127.0.0.1:1514: connect: connection refused" "${install_log}"; then
    if (( attempt >= max_attempts )); then
      echo "WARN: Harbor install failed after ${max_attempts} attempts due to logger startup race on 127.0.0.1:1514. Switching to serial fallback startup." >&2
      rm -f "${install_log}"
      if ! start_harbor_with_serial_log_bootstrap; then
        echo "ERROR: serial fallback startup failed." >&2
        exit 1
      fi
      break
    fi
    echo "WARN: Harbor install hit transient logger startup race (127.0.0.1:1514). Retrying in 5 seconds (attempt ${attempt}/${max_attempts})..." >&2
    rm -f "${install_log}"
    sleep 5
    ((attempt++))
    continue
  fi

  rm -f "${install_log}"
  echo "ERROR: Harbor install failed for a non-retryable reason." >&2
  exit 1
done

if ! reconcile_db_password_if_needed; then
  echo "ERROR: Harbor database credential reconciliation failed." >&2
  exit 1
fi

# Optional lifecycle unit. Harbor still uses Docker Compose underneath.
install -m 0644 "${BUNDLE_DIR}/systemd/harbor.service" /etc/systemd/system/harbor.service
systemctl daemon-reload
systemctl enable harbor.service || true

echo "INFO: Harbor install script finished."
