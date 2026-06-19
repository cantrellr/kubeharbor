#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat >&2 <<'EOF_WARN'
WARNING: tools/install-image-airgap-bundle.sh is deprecated.

kubeharbor now uses the k8s-airgap-images repository instead of the legacy
image-airgap-bundle-updated.zip image-list bundle.

Use:
  sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace

This compatibility shim is forwarding your arguments to install-k8s-airgap-images.sh.
EOF_WARN

exec "${SCRIPT_DIR}/install-k8s-airgap-images.sh" "$@"
