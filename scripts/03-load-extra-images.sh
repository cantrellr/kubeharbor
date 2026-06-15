#!/usr/bin/env bash
set -euo pipefail

echo "==> Loading extra offline Docker images"

[[ "${LOAD_EXTRA_IMAGES}" == "true" ]] || { echo "INFO: LOAD_EXTRA_IMAGES=false; skipping."; exit 0; }

shopt -s nullglob
images=("${BUNDLE_DIR}"/images/*.tar "${BUNDLE_DIR}"/images/*.tar.gz "${BUNDLE_DIR}"/images/*.tgz)
if (( ${#images[@]} == 0 )); then
  echo "WARN: no extra image archives found under ${BUNDLE_DIR}/images; skipping." >&2
  exit 0
fi

for image_archive in "${images[@]}"; do
  echo "INFO: docker load -i ${image_archive}"
  docker load -i "${image_archive}"
done

if [[ -n "${DHI_HARBOR_PORTAL_IMAGE}" ]]; then
  if docker image inspect "${DHI_HARBOR_PORTAL_IMAGE}" >/dev/null 2>&1; then
    echo "INFO: DHI portal image is present: ${DHI_HARBOR_PORTAL_IMAGE}"
  else
    echo "WARN: DHI portal image not found after load: ${DHI_HARBOR_PORTAL_IMAGE}" >&2
  fi
fi
