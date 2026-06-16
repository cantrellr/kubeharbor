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
IMAGE_LIST=""
FORCE_ARGS=()

usage() {
  cat <<EOF_USAGE
Usage:
  sudo ./tools/pull-images-to-data-cache.sh [--list image-lists/all-active-images.list] [--force]

Purpose:
  Pull all listed images into the local Docker cache. Docker/containerd must be configured with /data-backed storage before running this.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      IMAGE_LIST="$2"; shift 2 ;;
    --force|--force-pull)
      FORCE_ARGS+=("--force"); shift ;;
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
  echo "ERROR: DockerRootDir is '${root_dir}', not under /data." >&2
  echo "Fix Docker data-root before pulling 1,000+ images or the OS disk will fill." >&2
  exit 1
fi

mkdir -p "${IMAGE_TRANSFER_ROOT}/logs"
cd "${IMAGE_TRANSFER_ROOT}"

args=(pull)
if [[ -n "${IMAGE_LIST}" ]]; then args+=(--list "${IMAGE_LIST}"); fi
args+=("${FORCE_ARGS[@]}")

LOG_DIR="${IMAGE_TRANSFER_ROOT}/logs" CONTAINER_CLI=docker ./image-airgap.sh "${args[@]}"

echo "INFO: Docker image cache: ${root_dir}"
echo "INFO: Image transfer logs: ${IMAGE_TRANSFER_ROOT}/logs"
