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

# The offline installer includes Harbor's official image tarball. install.sh loads it locally and generates docker-compose.yml.
./install.sh "${args[@]}"

# Optional lifecycle unit. Harbor still uses Docker Compose underneath.
install -m 0644 "${BUNDLE_DIR}/systemd/harbor.service" /etc/systemd/system/harbor.service
systemctl daemon-reload
systemctl enable harbor.service || true

echo "INFO: Harbor install script finished."
