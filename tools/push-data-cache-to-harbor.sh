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
K8S_AIRGAP_IMAGES_CLI="${K8S_AIRGAP_IMAGES_CLI:-}"
TARGET_PREFIX="${TARGET_PREFIX:-${HARBOR_HOSTNAME:-kubeharbor.dev.kube}/library}"
PUSH_MODE="${PUSH_MODE:-strip-registry}"
IMAGE_LIST=""

usage() {
  cat <<EOF_USAGE
Usage:
  sudo ./tools/push-data-cache-to-harbor.sh [--target kubeharbor.dev.kube/library] [--mode strip-registry|preserve-registry] [--list image-lists/all-active-images.list]

Purpose:
  After the Internet-connected VM has been cloned/re-IP'd into the air-gapped environment,
  use the staged k8s-airgap-images repository to push locally cached images into Harbor.

Prerequisite:
  sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace
EOF_USAGE
}

find_airgap_cli() {
  local candidates=()

  if [[ -n "${K8S_AIRGAP_IMAGES_CLI}" ]]; then
    candidates+=("${K8S_AIRGAP_IMAGES_CLI}")
  fi

  candidates+=(
    "${IMAGE_TRANSFER_ROOT}/image-airgap.sh"
    "${IMAGE_TRANSFER_ROOT}/k8s-airgap-images.sh"
    "${IMAGE_TRANSFER_ROOT}/airgap-images.sh"
    "${IMAGE_TRANSFER_ROOT}/tools/image-airgap.sh"
    "${IMAGE_TRANSFER_ROOT}/tools/k8s-airgap-images.sh"
    "${IMAGE_TRANSFER_ROOT}/scripts/image-airgap.sh"
    "${IMAGE_TRANSFER_ROOT}/scripts/k8s-airgap-images.sh"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      chmod +x "${candidate}" 2>/dev/null || true
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  find "${IMAGE_TRANSFER_ROOT}" -maxdepth 4 -type f \
    \( -name 'image-airgap.sh' -o -name 'k8s-airgap-images.sh' -o -name 'airgap-images.sh' \) \
    -print 2>/dev/null | head -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value" >&2; exit 1; }
      TARGET_PREFIX="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || { echo "ERROR: --mode requires a value" >&2; exit 1; }
      PUSH_MODE="$2"; shift 2 ;;
    --list)
      [[ $# -ge 2 ]] || { echo "ERROR: --list requires a value" >&2; exit 1; }
      IMAGE_LIST="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

case "${PUSH_MODE}" in
  strip-registry|preserve-registry) ;;
  *) echo "ERROR: invalid --mode '${PUSH_MODE}'. Use strip-registry or preserve-registry." >&2; exit 1 ;;
esac

[[ -d "${IMAGE_TRANSFER_ROOT}" ]] || {
  echo "ERROR: k8s-airgap-images is not staged at ${IMAGE_TRANSFER_ROOT}." >&2
  echo "Run: sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace" >&2
  exit 1
}

AIRGAP_CLI="$(find_airgap_cli || true)"
[[ -n "${AIRGAP_CLI}" && -f "${AIRGAP_CLI}" ]] || {
  echo "ERROR: no compatible k8s-airgap-images CLI found under ${IMAGE_TRANSFER_ROOT}." >&2
  echo "Expected one of: image-airgap.sh, k8s-airgap-images.sh, airgap-images.sh." >&2
  echo "Run: sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required." >&2; exit 1; }

root_dir="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
if [[ "${root_dir}" != /data/* ]]; then
  echo "WARNING: DockerRootDir is '${root_dir}', not under /data. Local cache may be on the OS disk." >&2
fi

mkdir -p "${IMAGE_TRANSFER_ROOT}/logs"
cd "${IMAGE_TRANSFER_ROOT}"

args=(push --target "${TARGET_PREFIX}" --mode "${PUSH_MODE}")
if [[ -n "${IMAGE_LIST}" ]]; then args+=(--list "${IMAGE_LIST}"); fi

LOG_DIR="${IMAGE_TRANSFER_ROOT}/logs" CONTAINER_CLI=docker "${AIRGAP_CLI}" "${args[@]}"

echo "INFO: Push workflow complete. Review logs under ${IMAGE_TRANSFER_ROOT}/logs"
