#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${BUNDLE_DIR}/config/harbor.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

IMAGE_TRANSFER_ROOT="${IMAGE_TRANSFER_ROOT:-/data/k8s-airgap-images}"
K8S_AIRGAP_IMAGES_SOURCE="${K8S_AIRGAP_IMAGES_SOURCE:-}"
K8S_AIRGAP_IMAGES_BRANCH="${K8S_AIRGAP_IMAGES_BRANCH:-main}"
REPLACE="false"
SOURCE_PATH=""

usage() {
  cat <<EOF_USAGE
Usage:
  sudo ./tools/install-k8s-airgap-images.sh [source] [--dest /data/k8s-airgap-images] [--branch main] [--replace]

Purpose:
  Stage the k8s-airgap-images repository under /data so large Kubernetes image pull/push
  workflows do not depend on the legacy image-airgap-bundle-updated.zip file.

Source options:
  - Local directory containing the k8s-airgap-images repo
  - Local .tgz, .tar.gz, .tar, or .zip archive of the repo
  - Git URL, for Internet-connected staging hosts only

If source is omitted, the script uses K8S_AIRGAP_IMAGES_SOURCE from config/harbor.env
or tries common local paths:
  ../k8s-airgap-images
  ./k8s-airgap-images
  /data/k8s-airgap-images-source
  /opt/k8s-airgap-images-source

Examples:
  sudo ./tools/install-k8s-airgap-images.sh ../k8s-airgap-images --replace
  sudo ./tools/install-k8s-airgap-images.sh /transfer/k8s-airgap-images.tgz --replace
  sudo K8S_AIRGAP_IMAGES_SOURCE=https://github.com/<owner>/k8s-airgap-images.git \
    ./tools/install-k8s-airgap-images.sh --replace
EOF_USAGE
}

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
err() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || err "missing command: $1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || err "--dest requires a value"
      IMAGE_TRANSFER_ROOT="$2"; shift 2 ;;
    --branch|--ref)
      [[ $# -ge 2 ]] || err "$1 requires a value"
      K8S_AIRGAP_IMAGES_BRANCH="$2"; shift 2 ;;
    --replace)
      REPLACE="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      if [[ -z "${SOURCE_PATH}" ]]; then
        SOURCE_PATH="$1"; shift
      else
        err "unexpected argument: $1"
      fi ;;
  esac
done

if [[ -z "${SOURCE_PATH}" ]]; then
  SOURCE_PATH="${K8S_AIRGAP_IMAGES_SOURCE}"
fi

if [[ -z "${SOURCE_PATH}" ]]; then
  for candidate in \
    "${BUNDLE_DIR}/../k8s-airgap-images" \
    "${BUNDLE_DIR}/k8s-airgap-images" \
    "/data/k8s-airgap-images-source" \
    "/opt/k8s-airgap-images-source"; do
    if [[ -e "${candidate}" ]]; then
      SOURCE_PATH="${candidate}"
      break
    fi
  done
fi

[[ -n "${SOURCE_PATH}" ]] || {
  usage >&2
  err "k8s-airgap-images source is required. Provide a source path/URL or set K8S_AIRGAP_IMAGES_SOURCE."
}

if [[ "${IMAGE_TRANSFER_ROOT}" != /data/* ]]; then
  warn "IMAGE_TRANSFER_ROOT=${IMAGE_TRANSFER_ROOT} is not under /data. Continuing, but this is not recommended for large image workflows."
fi

mkdir -p "$(dirname "${IMAGE_TRANSFER_ROOT}")"

find_compatible_root() {
  local root="$1"
  local found=""

  if [[ -f "${root}/image-airgap.sh" || -f "${root}/k8s-airgap-images.sh" ]]; then
    printf '%s\n' "${root}"
    return 0
  fi

  found="$(find "${root}" -maxdepth 4 -type f \
    \( -name 'image-airgap.sh' -o -name 'k8s-airgap-images.sh' -o -name 'airgap-images.sh' \) \
    -printf '%h\n' 2>/dev/null | head -1 || true)"

  if [[ -n "${found}" ]]; then
    # Prefer the repository root when the executable lives in a tools/ or scripts/ subdirectory.
    case "$(basename "${found}")" in
      tools|script|scripts|bin)
        printf '%s\n' "$(dirname "${found}")"
        ;;
      *)
        printf '%s\n' "${found}"
        ;;
    esac
    return 0
  fi

  return 1
}

install_from_dir() {
  local source_dir="$1"
  local compatible_root
  compatible_root="$(find_compatible_root "${source_dir}")" || err "No compatible image utility found in ${source_dir}. Expected image-airgap.sh, k8s-airgap-images.sh, or airgap-images.sh."

  if [[ "$(readlink -f "${compatible_root}")" == "$(readlink -f "${IMAGE_TRANSFER_ROOT}" 2>/dev/null || true)" ]]; then
    log "k8s-airgap-images already staged at ${IMAGE_TRANSFER_ROOT}"
  else
    if [[ -e "${IMAGE_TRANSFER_ROOT}" ]]; then
      if [[ "${REPLACE}" != "true" ]]; then
        err "destination already exists: ${IMAGE_TRANSFER_ROOT}. Use --replace to remove and recreate it."
      fi
      rm -rf "${IMAGE_TRANSFER_ROOT}"
    fi

    mkdir -p "$(dirname "${IMAGE_TRANSFER_ROOT}")"
    cp -a "${compatible_root}" "${IMAGE_TRANSFER_ROOT}"
  fi
}

install_from_archive() {
  local archive="$1"
  local workdir
  workdir="$(mktemp -d /tmp/kubeharbor-k8s-airgap-images.XXXXXX)"
  cleanup_archive() { rm -rf "${workdir}"; }
  trap cleanup_archive RETURN

  case "${archive}" in
    *.zip)
      need_cmd unzip
      unzip -q "${archive}" -d "${workdir}"
      ;;
    *.tgz|*.tar.gz)
      tar -xzf "${archive}" -C "${workdir}"
      ;;
    *.tar)
      tar -xf "${archive}" -C "${workdir}"
      ;;
    *)
      err "unsupported archive type: ${archive}"
      ;;
  esac

  install_from_dir "${workdir}"
}

install_from_git() {
  local url="$1"
  local workdir
  need_cmd git

  workdir="$(mktemp -d /tmp/kubeharbor-k8s-airgap-images-git.XXXXXX)"
  cleanup_git() { rm -rf "${workdir}"; }
  trap cleanup_git RETURN

  log "Cloning k8s-airgap-images from ${url} ref ${K8S_AIRGAP_IMAGES_BRANCH}"
  git clone --depth 1 --branch "${K8S_AIRGAP_IMAGES_BRANCH}" "${url}" "${workdir}/k8s-airgap-images"
  install_from_dir "${workdir}/k8s-airgap-images"
}

case "${SOURCE_PATH}" in
  http://*|https://*|git@*|ssh://*)
    install_from_git "${SOURCE_PATH}"
    ;;
  *.zip|*.tgz|*.tar.gz|*.tar)
    [[ -f "${SOURCE_PATH}" ]] || err "archive not found: ${SOURCE_PATH}"
    install_from_archive "${SOURCE_PATH}"
    ;;
  *)
    [[ -d "${SOURCE_PATH}" ]] || err "source directory not found: ${SOURCE_PATH}"
    install_from_dir "${SOURCE_PATH}"
    ;;
esac

find "${IMAGE_TRANSFER_ROOT}" -maxdepth 3 -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
mkdir -p "${IMAGE_TRANSFER_ROOT}/logs"
printf 'source=%s\ninstalled_at=%s\ninstalled_on=%s\n' \
  "${SOURCE_PATH}" "${IMAGE_TRANSFER_ROOT}" "$(date -Is)" > "${IMAGE_TRANSFER_ROOT}/.kubeharbor-source"

ln -sfn "${IMAGE_TRANSFER_ROOT}" /opt/k8s-airgap-images
ln -sfn "${IMAGE_TRANSFER_ROOT}" /opt/kubeharbor-image-transfer

cat <<EOF_DONE
SUCCESS: k8s-airgap-images staged.
Path:          ${IMAGE_TRANSFER_ROOT}
Symlink:       /opt/k8s-airgap-images
Compat link:   /opt/kubeharbor-image-transfer
Next pull:     sudo ./tools/pull-images-to-data-cache.sh
Next push:     sudo ./tools/push-data-cache-to-harbor.sh
EOF_DONE
