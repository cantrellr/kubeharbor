#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${BUNDLE_DIR}/config/harbor.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

IMAGE_TRANSFER_ROOT="${IMAGE_TRANSFER_ROOT:-/data/kubeharbor-image-transfer}"
TARGET_PREFIX="${TARGET_PREFIX:-${HARBOR_HOSTNAME:-kubeharbor.dev.kube}/library}"
PUSH_MODE="${PUSH_MODE:-strip-registry}"
IMAGE_LIST=""

usage() {
  cat <<EOF_USAGE
Usage:
  sudo ./tools/push-data-cache-to-harbor.sh [--target kubeharbor.dev.kube/library] [--mode strip-registry|preserve-registry] [--list image-lists/all-active-images.list]

Purpose:
  After the Internet-connected VM has been cloned/re-IP'd into the air-gapped environment, push the locally cached images into the reachable Harbor registry.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_PREFIX="$2"; shift 2 ;;
    --mode)
      PUSH_MODE="$2"; shift 2 ;;
    --list)
      IMAGE_LIST="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -x "${IMAGE_TRANSFER_ROOT}/image-airgap.sh" ]] || {
  echo "ERROR: missing image-airgap utility at ${IMAGE_TRANSFER_ROOT}." >&2
  echo "Run: sudo ./tools/install-image-airgap-bundle.sh /path/to/image-airgap-bundle-updated.zip --replace" >&2
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

LOG_DIR="${IMAGE_TRANSFER_ROOT}/logs" CONTAINER_CLI=docker ./image-airgap.sh "${args[@]}"

echo "INFO: Push workflow complete. Review logs under ${IMAGE_TRANSFER_ROOT}/logs"
