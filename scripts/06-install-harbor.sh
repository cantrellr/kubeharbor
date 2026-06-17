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

wait_for_harbor_log_listener() {
  local ready="false"
  for _ in {1..20}; do
    if ss -ltn '( sport = :1514 )' 2>/dev/null | grep -q ':1514'; then
      ready="true"
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != "true" ]]; then
    echo "ERROR: harbor-log listener on 127.0.0.1:1514 did not become ready." >&2
    return 1
  fi
}

start_harbor_with_serial_log_bootstrap() {
  echo "INFO: starting Harbor with serial startup: bootstrap harbor-log first, then start remaining services."

  prepare_args=()
  if [[ "${INSTALL_TRIVY}" == "true" ]]; then
    prepare_args+=("--with-trivy")
  fi

  shopt -s nullglob
  harbor_image_archives=(./harbor*.tar.gz)
  shopt -u nullglob
  if (( ${#harbor_image_archives[@]} > 0 )); then
    echo "INFO: loading Harbor offline images from ${harbor_image_archives[*]}"
    docker load -i "${harbor_image_archives[0]}"
  fi

  ./prepare "${prepare_args[@]}"
  docker compose down -v || true
  docker compose up -d log

  if ! wait_for_harbor_log_listener; then
    echo "ERROR: serial Harbor startup failed while waiting for harbor-log readiness." >&2
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

if ! start_harbor_with_serial_log_bootstrap; then
  echo "ERROR: Harbor serial startup failed." >&2
  exit 1
fi

if ! reconcile_db_password_if_needed; then
  echo "ERROR: Harbor database credential reconciliation failed." >&2
  exit 1
fi

# Optional lifecycle unit. Harbor still uses Docker Compose underneath.
install -m 0644 "${BUNDLE_DIR}/systemd/harbor.service" /etc/systemd/system/harbor.service
install -m 0755 "${BUNDLE_DIR}/scripts/11-start-harbor-serial.sh" /usr/local/sbin/harbor-start-serial.sh
install -m 0755 "${BUNDLE_DIR}/scripts/12-reset-harbor.sh" /usr/local/sbin/harbor-reset.sh
systemctl daemon-reload
systemctl enable harbor.service || true

echo "INFO: Harbor install script finished."
