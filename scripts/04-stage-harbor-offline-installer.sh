#!/usr/bin/env bash
set -euo pipefail

echo "==> Staging Harbor offline installer"

shopt -s nullglob
installers=("${BUNDLE_DIR}"/installers/harbor-offline-installer-*.tgz)
if (( ${#installers[@]} != 1 )); then
  echo "ERROR: expected exactly one Harbor offline installer under installers/." >&2
  exit 1
fi
installer="${installers[0]}"

mkdir -p "${HARBOR_INSTALL_PARENT}"

tmp_extract_dir="${HARBOR_INSTALL_PARENT}/.harbor-extract-$$"
backup_dir=""

if [[ -d "${HARBOR_INSTALL_DIR}" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${HARBOR_INSTALL_DIR}.bak-${stamp}"
  echo "INFO: existing ${HARBOR_INSTALL_DIR} found; backing up to ${backup_dir}"
  mv "${HARBOR_INSTALL_DIR}" "${backup_dir}"
fi

cleanup_failed_stage() {
  if [[ -d "${tmp_extract_dir}" ]]; then
    rm -rf "${tmp_extract_dir}"
  fi
  if [[ ! -d "${HARBOR_INSTALL_DIR}" && -n "${backup_dir}" && -d "${backup_dir}" ]]; then
    echo "WARN: staging failed; restoring previous Harbor directory from ${backup_dir}" >&2
    mv "${backup_dir}" "${HARBOR_INSTALL_DIR}"
  fi
}
trap cleanup_failed_stage ERR

mkdir -p "${tmp_extract_dir}"
tar -xzf "$installer" -C "${tmp_extract_dir}"

if [[ ! -d "${tmp_extract_dir}/harbor" ]]; then
  echo "ERROR: extracted installer did not include harbor/ directory" >&2
  exit 1
fi

mv "${tmp_extract_dir}/harbor" "${HARBOR_INSTALL_DIR}"
rm -rf "${tmp_extract_dir}"
trap - ERR

portal_nginx_conf="${HARBOR_INSTALL_DIR}/common/config/portal/nginx.conf"
if [[ -d "${portal_nginx_conf}" ]]; then
  echo "WARN: ${portal_nginx_conf} is a directory; restoring file form before Harbor prepare step."
  rm -rf "${portal_nginx_conf}"
  if [[ -f "${backup_dir}/common/config/portal/nginx.conf" ]]; then
    install -m 0644 "${backup_dir}/common/config/portal/nginx.conf" "${portal_nginx_conf}"
  else
    : > "${portal_nginx_conf}"
    chmod 0644 "${portal_nginx_conf}"
  fi
fi

if [[ ! -f "${HARBOR_INSTALL_DIR}/install.sh" ]]; then
  echo "ERROR: extracted installer did not produce ${HARBOR_INSTALL_DIR}/install.sh" >&2
  exit 1
fi

chmod +x "${HARBOR_INSTALL_DIR}/install.sh" || true
[[ -x "${HARBOR_INSTALL_DIR}/prepare" ]] && chmod +x "${HARBOR_INSTALL_DIR}/prepare" || true

echo "INFO: Harbor installer staged at ${HARBOR_INSTALL_DIR}."
