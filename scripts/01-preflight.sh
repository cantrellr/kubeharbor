#!/usr/bin/env bash
set -euo pipefail

echo "==> Preflight checks"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

require_var() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    fail "Required setting ${name} is empty. Fix config/harbor.env."
  fi
}

verify_checksums_in_dir() {
  local rel_dir="$1"
  local sum_file="${BUNDLE_DIR}/${rel_dir}/SHA256SUMS"
  local dir="${BUNDLE_DIR}/${rel_dir}"
  local line expected file_ref file_name file_path actual

  [[ -f "$sum_file" ]] || fail "Missing checksum file: ${sum_file}"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    expected="$(awk '{print $1}' <<<"$line")"
    file_ref="$(awk '{print $2}' <<<"$line")"
    if [[ -z "$expected" || -z "$file_ref" ]]; then
      fail "Malformed checksum line in ${sum_file}: ${line}"
    fi
    file_name="$(basename "$file_ref")"
    file_path="${dir}/${file_name}"
    [[ -f "$file_path" ]] || fail "Checksum target missing: ${file_path}"
    actual="$(sha256sum "$file_path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      fail "Checksum mismatch for ${file_path}"
    fi
  done < "$sum_file"

  echo "INFO: checksum verification passed for ${rel_dir}"
}

[[ -n "${BUNDLE_DIR:-}" ]] || fail "BUNDLE_DIR is not set"
[[ -f "${ENV_FILE:-}" ]] || fail "ENV_FILE is not set or missing"

required_vars=(
  HARBOR_HOSTNAME
  HARBOR_VERSION
  HARBOR_CONFIG_VERSION
  HARBOR_DATA_VOLUME
  HARBOR_INSTALL_DIR
  HARBOR_LEAF_CERT_SOURCE
  HARBOR_LEAF_KEY_SOURCE
  HARBOR_ADMIN_PASSWORD
  HARBOR_DB_PASSWORD
)
for v in "${required_vars[@]}"; do
  require_var "$v"
done

if [[ "${HARBOR_ADMIN_PASSWORD}" == CHANGE-ME-* ]]; then
  fail "Set HARBOR_ADMIN_PASSWORD in config/harbor.env before deployment."
fi
if [[ "${HARBOR_DB_PASSWORD}" == CHANGE-ME-* ]]; then
  fail "Set HARBOR_DB_PASSWORD in config/harbor.env before deployment."
fi
if (( ${#HARBOR_ADMIN_PASSWORD} < 16 )); then
  fail "HARBOR_ADMIN_PASSWORD must be at least 16 characters."
fi
if (( ${#HARBOR_DB_PASSWORD} < 16 )); then
  fail "HARBOR_DB_PASSWORD must be at least 16 characters."
fi

command -v tar >/dev/null || fail "tar is required"
command -v openssl >/dev/null || fail "openssl is required"
command -v python3 >/dev/null || fail "python3 is required to render harbor.yml"
command -v sha256sum >/dev/null || fail "sha256sum is required"

if [[ ! -f "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" ]]; then
  fail "Missing Harbor TLS leaf cert: ${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}"
fi
if [[ ! -f "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" ]]; then
  fail "Missing Harbor TLS leaf private key: ${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}"
fi
if [[ -n "${HARBOR_CA_CERT_SOURCE}" && ! -f "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" ]]; then
  warn "Missing CA cert ${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}. Harbor can still run, but client trust distribution will be manual."
fi

openssl x509 -in "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" -noout >/dev/null || fail "Leaf certificate is not readable by openssl."
openssl rsa -in "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" -check -noout >/dev/null 2>&1 || fail "Leaf private key failed openssl validation."

if ! openssl x509 -in "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" -noout -checkhost "${HARBOR_HOSTNAME}" >/dev/null; then
  fail "Leaf certificate does not include ${HARBOR_HOSTNAME} in SAN/CN."
fi

cert_pubkey="$(openssl x509 -in "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum | awk '{print $1}')"
key_pubkey="$(openssl pkey -in "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" -pubout -outform DER | sha256sum | awk '{print $1}')"
if [[ "$cert_pubkey" != "$key_pubkey" ]]; then
  fail "Leaf certificate and private key do not match."
fi

if [[ -n "${HARBOR_CA_CERT_SOURCE}" && -f "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" ]]; then
  openssl verify -CAfile "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" >/dev/null || fail "Leaf certificate failed CA chain verification."
fi

shopt -s nullglob
installers=("${BUNDLE_DIR}"/installers/harbor-offline-installer-*.tgz)
if (( ${#installers[@]} != 1 )); then
  fail "Place exactly one Harbor offline installer in installers/: harbor-offline-installer-<version>.tgz"
fi

installer_base="$(basename "${installers[0]}")"
if [[ "$installer_base" != "harbor-offline-installer-${HARBOR_VERSION}.tgz" ]]; then
  fail "Installer filename ${installer_base} does not match HARBOR_VERSION=${HARBOR_VERSION}."
fi

if [[ "${HARBOR_VERSION#v}" != "${HARBOR_CONFIG_VERSION}" ]]; then
  fail "HARBOR_CONFIG_VERSION (${HARBOR_CONFIG_VERSION}) must match HARBOR_VERSION without v (${HARBOR_VERSION#v})."
fi

verify_checksums_in_dir "installers"

if [[ "${INSTALL_DOCKER}" == "true" ]]; then
  debs=("${BUNDLE_DIR}"/packages/docker-debs/*.deb)
  if (( ${#debs[@]} == 0 )); then
    fail "INSTALL_DOCKER=true but no Docker .deb files found under packages/docker-debs/."
  fi
  verify_checksums_in_dir "packages/docker-debs"
fi

if [[ "${LOAD_EXTRA_IMAGES}" == "true" ]]; then
  images=("${BUNDLE_DIR}"/images/*.tar "${BUNDLE_DIR}"/images/*.tar.gz "${BUNDLE_DIR}"/images/*.tgz)
  if (( ${#images[@]} == 0 )); then
    warn "LOAD_EXTRA_IMAGES=true but no image archives found under images/."
  else
    verify_checksums_in_dir "images"
  fi
fi

if [[ "${USE_DHI_HARBOR_PORTAL}" == "true" && "${LOAD_EXTRA_IMAGES}" != "true" ]]; then
  fail "USE_DHI_HARBOR_PORTAL=true requires LOAD_EXTRA_IMAGES=true so the portal image can be loaded."
fi
if [[ "${USE_DHI_HARBOR_PORTAL}" == "true" && -z "${DHI_HARBOR_PORTAL_IMAGE:-}" ]]; then
  fail "USE_DHI_HARBOR_PORTAL=true requires DHI_HARBOR_PORTAL_IMAGE to be set."
fi

cpu_count="$(nproc || echo 0)"
mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
root_free_gb="$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
lab_override="${ALLOW_UNDERSIZED_LAB:-false}"

if (( cpu_count < 4 )); then
  if [[ "$lab_override" == "true" ]]; then
    warn "CPU count is ${cpu_count}; continuing because ALLOW_UNDERSIZED_LAB=true."
  else
    fail "CPU count is ${cpu_count}; this deployment baseline requires at least 4 vCPU."
  fi
fi
if (( mem_mb < 15000 )); then
  if [[ "$lab_override" == "true" ]]; then
    warn "RAM is ${mem_mb} MB; continuing because ALLOW_UNDERSIZED_LAB=true."
  else
    warn "RAM is ${mem_mb} MB; target is 16 GB. Continuing because some hypervisors report slightly under."
  fi
fi
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
