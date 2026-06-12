#!/usr/bin/env bash
set -euo pipefail

echo "==> Preflight checks"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

[[ -n "${BUNDLE_DIR:-}" ]] || fail "BUNDLE_DIR is not set"
[[ -f "${ENV_FILE:-}" ]] || fail "ENV_FILE is not set or missing"

if [[ "${HARBOR_ADMIN_PASSWORD}" == CHANGE-ME-* ]]; then
  fail "Set HARBOR_ADMIN_PASSWORD in config/harbor.env before deployment."
fi
if [[ "${HARBOR_DB_PASSWORD}" == CHANGE-ME-* ]]; then
  fail "Set HARBOR_DB_PASSWORD in config/harbor.env before deployment."
fi

command -v tar >/dev/null || fail "tar is required"
command -v openssl >/dev/null || fail "openssl is required"
command -v python3 >/dev/null || fail "python3 is required to render harbor.yml"

if [[ ! -f "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" ]]; then
  fail "Missing Harbor TLS leaf cert: ${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}"
fi
if [[ ! -f "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" ]]; then
  fail "Missing Harbor TLS leaf private key: ${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}"
fi
if [[ -n "${HARBOR_CA_CERT_SOURCE}" && ! -f "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" ]]; then
  warn "Missing CA cert ${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}. Harbor can still run, but client trust distribution will be manual."
fi
if [[ -f "${BUNDLE_DIR}/${HARBOR_CA_KEY_SOURCE}" ]]; then
  warn "CA private key found in bundle. Harbor does not need it. Remove it from the VM after certificate work is complete."
fi

openssl x509 -in "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" -noout >/dev/null || fail "Leaf certificate is not readable by openssl."
openssl rsa -in "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" -check -noout >/dev/null 2>&1 || fail "Leaf private key failed openssl validation."

shopt -s nullglob
installers=("${BUNDLE_DIR}"/installers/harbor-offline-installer-*.tgz)
if (( ${#installers[@]} != 1 )); then
  fail "Place exactly one Harbor offline installer in installers/: harbor-offline-installer-<version>.tgz"
fi

if [[ "${INSTALL_DOCKER}" == "true" ]]; then
  debs=("${BUNDLE_DIR}"/packages/docker-debs/*.deb)
  if (( ${#debs[@]} == 0 )); then
    fail "INSTALL_DOCKER=true but no Docker .deb files found under packages/docker-debs/."
  fi
fi

if [[ "${LOAD_EXTRA_IMAGES}" == "true" ]]; then
  images=("${BUNDLE_DIR}"/images/*.tar "${BUNDLE_DIR}"/images/*.tar.gz "${BUNDLE_DIR}"/images/*.tgz)
  if (( ${#images[@]} == 0 )); then
    warn "LOAD_EXTRA_IMAGES=true but no image archives found under images/."
  fi
fi

cpu_count="$(nproc || echo 0)"
mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
root_free_gb="$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"

if (( cpu_count < 4 )); then fail "CPU count is ${cpu_count}; this deployment baseline requires at least 4 vCPU."; fi
if (( mem_mb < 15000 )); then warn "RAM is ${mem_mb} MB; target is 16 GB. Continuing because some hypervisors report slightly under."; fi
if (( root_free_gb < 25 )); then warn "Root filesystem has only ${root_free_gb} GB free. 64 GB OS disk is okay, but Docker image staging can still get tight."; fi

if ! findmnt -rn "${HARBOR_DATA_VOLUME}" >/dev/null 2>&1; then
  fail "${HARBOR_DATA_VOLUME} is not mounted. Fix data disk mount before deploying."
fi

data_free_gb="$(df -BG "${HARBOR_DATA_VOLUME}" | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
if (( data_free_gb < 400 )); then
  warn "${HARBOR_DATA_VOLUME} has ${data_free_gb} GB free; expected around 500 GB data drive."
fi

mkdir -p "${HARBOR_LOG_DIR}" "${HARBOR_INSTALL_PARENT}"

echo "INFO: preflight passed."
