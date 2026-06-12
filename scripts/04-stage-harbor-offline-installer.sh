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

if [[ -d "${HARBOR_INSTALL_DIR}" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  echo "INFO: existing ${HARBOR_INSTALL_DIR} found; backing up to ${HARBOR_INSTALL_DIR}.bak-${stamp}"
  mv "${HARBOR_INSTALL_DIR}" "${HARBOR_INSTALL_DIR}.bak-${stamp}"
fi

tar -xzf "$installer" -C "${HARBOR_INSTALL_PARENT}"

if [[ ! -x "${HARBOR_INSTALL_DIR}/install.sh" ]]; then
  echo "ERROR: extracted installer did not produce ${HARBOR_INSTALL_DIR}/install.sh" >&2
  exit 1
fi

chmod +x "${HARBOR_INSTALL_DIR}/install.sh" || true
[[ -x "${HARBOR_INSTALL_DIR}/prepare" ]] && chmod +x "${HARBOR_INSTALL_DIR}/prepare" || true

echo "INFO: Harbor installer staged at ${HARBOR_INSTALL_DIR}."
