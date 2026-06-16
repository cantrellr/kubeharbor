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
REPLACE="false"
ZIP_PATH=""

usage() {
  cat <<EOF_USAGE
Usage:
  sudo ./tools/install-image-airgap-bundle.sh /path/to/image-airgap-bundle-updated.zip [--dest /data/kubeharbor-image-transfer] [--replace]

Purpose:
  Extract the image pull/push utility bundle onto /data so lists, logs, and operational state do not land on the 64 GB OS disk.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      IMAGE_TRANSFER_ROOT="$2"; shift 2 ;;
    --replace)
      REPLACE="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      if [[ -z "${ZIP_PATH}" ]]; then ZIP_PATH="$1"; shift; else echo "ERROR: unexpected argument: $1" >&2; usage; exit 1; fi ;;
  esac
done

[[ -n "${ZIP_PATH}" ]] || { echo "ERROR: ZIP path is required." >&2; usage; exit 1; }
[[ -f "${ZIP_PATH}" ]] || { echo "ERROR: ZIP not found: ${ZIP_PATH}" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip is required." >&2; exit 1; }

if [[ "${IMAGE_TRANSFER_ROOT}" != /data/* ]]; then
  echo "WARNING: IMAGE_TRANSFER_ROOT=${IMAGE_TRANSFER_ROOT} is not under /data. Continuing, but this is not recommended." >&2
fi

if [[ -e "${IMAGE_TRANSFER_ROOT}" ]]; then
  if [[ "${REPLACE}" != "true" ]]; then
    echo "ERROR: destination already exists: ${IMAGE_TRANSFER_ROOT}" >&2
    echo "Use --replace to remove and recreate it." >&2
    exit 1
  fi
  rm -rf "${IMAGE_TRANSFER_ROOT}"
fi

workdir="$(mktemp -d /data/kubeharbor-image-bundle.XXXXXX)"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

unzip -q "${ZIP_PATH}" -d "${workdir}"
source_dir="$(find "${workdir}" -maxdepth 2 -type f -name image-airgap.sh -printf '%h\n' | head -1)"
[[ -n "${source_dir}" ]] || { echo "ERROR: image-airgap.sh not found in ${ZIP_PATH}" >&2; exit 1; }

mkdir -p "$(dirname "${IMAGE_TRANSFER_ROOT}")"
cp -a "${source_dir}" "${IMAGE_TRANSFER_ROOT}"
chmod +x "${IMAGE_TRANSFER_ROOT}"/*.sh 2>/dev/null || true
mkdir -p "${IMAGE_TRANSFER_ROOT}/logs"

ln -sfn "${IMAGE_TRANSFER_ROOT}" /opt/kubeharbor-image-transfer

cat <<EOF_DONE
SUCCESS: image air-gap utility installed.
Path:      ${IMAGE_TRANSFER_ROOT}
Symlink:   /opt/kubeharbor-image-transfer
Next pull: sudo ./tools/pull-images-to-data-cache.sh
Next push: sudo ./tools/push-data-cache-to-harbor.sh
EOF_DONE
