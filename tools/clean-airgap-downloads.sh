#!/usr/bin/env bash
set -euo pipefail

# Clean generated/downloaded artifacts from the kubeharbor air-gap bundle so the
# Internet-connected staging workflow can start from a clean slate.
#
# Safe default behavior removes only generated files inside this bundle plus
# known /tmp scratch directories. It does not remove certificates, deployed
# Harbor runtime data, Docker Engine packages installed on the host, or Docker
# images unless explicitly requested.

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSUME_YES="false"
DRY_RUN="false"
PURGE_DOCKER_IMAGES="false"
PURGE_DOCKER_AUTH="false"
PRUNE_CONTAINERS="false"
PURGE_CERTS="false"
PURGE_TMP="true"

usage() {
  cat <<USAGE
Usage: sudo ./tools/clean-airgap-downloads.sh [options]

Removes downloaded/generated air-gap artifacts from this bundle so the next
staging run starts clean.

Default cleanup:
  - output/*.tgz and output/*.sha256
  - packages/docker-debs/*.deb
  - packages/docker-debs/SHA256SUMS and DOCKER_PACKAGE_LIST.txt
  - installers/harbor-offline-installer-*.tgz and release sidecars
  - installers/SHA256SUMS
  - images/*.tar, *.inspect.json, DHI_IMAGE_REF.txt, SHA256SUMS
  - sbom/generated SBOM and provenance files, preserving sbom/README.md
  - ARTIFACTS.txt
  - /tmp/kubeharbor-docker-debs and /tmp/kubeharbor-docker-config.*

Options:
  -y, --yes                 Do not prompt for confirmation.
      --dry-run             Show what would be removed, but do not remove it.
      --purge-docker-images Remove the staged DHI image from the local Docker image cache if present.
      --purge-docker-auth   Remove Docker auth files left by older runs, including /root/.docker/config.json.
      --prune-containers    Stop and remove all Docker containers on this host.
      --purge-certs         Remove certs/*.crt, certs/*.key, certs/*.pem, certs/*.csr, certs/*.srl.
      --no-tmp              Do not remove /tmp scratch directories.
  -h, --help                Show this help.

Examples:
  sudo ./tools/clean-airgap-downloads.sh --yes
  sudo ./tools/clean-airgap-downloads.sh --dry-run
  sudo ./tools/clean-airgap-downloads.sh --yes --purge-docker-images --purge-docker-auth
  sudo ./tools/clean-airgap-downloads.sh --yes --prune-containers
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES="true" ;;
    --dry-run) DRY_RUN="true" ;;
    --purge-docker-images) PURGE_DOCKER_IMAGES="true" ;;
    --purge-docker-auth) PURGE_DOCKER_AUTH="true" ;;
    --prune-containers) PRUNE_CONTAINERS="true" ;;
    --purge-certs) PURGE_CERTS="true" ;;
    --no-tmp) PURGE_TMP="false" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

# Capture the DHI image reference before deleting bundle files.
DHI_IMAGE_REF=""
if [[ -f "${BUNDLE_DIR}/images/DHI_IMAGE_REF.txt" ]]; then
  DHI_IMAGE_REF="$(tr -d '\r\n' < "${BUNDLE_DIR}/images/DHI_IMAGE_REF.txt" || true)"
fi
if [[ -z "${DHI_IMAGE_REF}" && -f "${BUNDLE_DIR}/config/harbor.env" ]]; then
  # shellcheck disable=SC1090
  source "${BUNDLE_DIR}/config/harbor.env" || true
  DHI_IMAGE_REF="${DHI_HARBOR_PORTAL_IMAGE:-}"
fi

paths_to_remove=()
add_glob() {
  local pattern="$1"
  shopt -s nullglob
  local matches=( $pattern )
  shopt -u nullglob
  if [[ ${#matches[@]} -gt 0 ]]; then
    paths_to_remove+=("${matches[@]}")
  fi
}

add_path_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    paths_to_remove+=("$path")
  fi
  return 0
}

add_glob "${BUNDLE_DIR}/output/*.tgz"
add_glob "${BUNDLE_DIR}/output/*.tgz.sha256"
add_glob "${BUNDLE_DIR}/output/*.sha256"

add_glob "${BUNDLE_DIR}/packages/docker-debs/*.deb"
add_path_if_exists "${BUNDLE_DIR}/packages/docker-debs/SHA256SUMS"
add_path_if_exists "${BUNDLE_DIR}/packages/docker-debs/DOCKER_PACKAGE_LIST.txt"

add_glob "${BUNDLE_DIR}/installers/harbor-offline-installer-*.tgz"
add_glob "${BUNDLE_DIR}/installers/harbor-offline-installer-*.tgz.*"
add_path_if_exists "${BUNDLE_DIR}/installers/SHA256SUMS"

add_glob "${BUNDLE_DIR}/images/*.tar"
add_glob "${BUNDLE_DIR}/images/*.inspect.json"
add_path_if_exists "${BUNDLE_DIR}/images/DHI_IMAGE_REF.txt"
add_path_if_exists "${BUNDLE_DIR}/images/SHA256SUMS"

add_glob "${BUNDLE_DIR}/sbom/*.json"
add_glob "${BUNDLE_DIR}/sbom/*.txt"
add_path_if_exists "${BUNDLE_DIR}/sbom/SHA256SUMS"

add_path_if_exists "${BUNDLE_DIR}/ARTIFACTS.txt"

if [[ "${PURGE_CERTS}" == "true" ]]; then
  add_glob "${BUNDLE_DIR}/certs/*.crt"
  add_glob "${BUNDLE_DIR}/certs/*.key"
  add_glob "${BUNDLE_DIR}/certs/*.pem"
  add_glob "${BUNDLE_DIR}/certs/*.csr"
  add_glob "${BUNDLE_DIR}/certs/*.srl"
fi

if [[ "${PURGE_TMP}" == "true" ]]; then
  add_path_if_exists "/tmp/kubeharbor-docker-debs"
  add_glob "/tmp/kubeharbor-docker-config.*"
fi

cat <<SUMMARY
Clean-slate request
Bundle directory:        ${BUNDLE_DIR}
Dry run:                 ${DRY_RUN}
Purge Docker images:     ${PURGE_DOCKER_IMAGES}
Purge Docker auth:       ${PURGE_DOCKER_AUTH}
Prune containers:        ${PRUNE_CONTAINERS}
Purge cert files:        ${PURGE_CERTS}
Purge temp directories:  ${PURGE_TMP}
SUMMARY

if [[ ${#paths_to_remove[@]} -eq 0 ]]; then
  log "No downloaded/generated bundle artifacts found. Bundle already looks clean."
else
  echo
  echo "Files/directories selected for removal:"
  printf '  %s\n' "${paths_to_remove[@]}"
fi

if [[ "${PURGE_DOCKER_AUTH}" == "true" ]]; then
  echo
  echo "Docker auth files selected for removal when present:"
  echo "  /root/.docker/config.json"
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    user_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
    [[ -n "${user_home}" ]] && echo "  ${user_home}/.docker/config.json"
  fi
fi

if [[ "${PURGE_DOCKER_IMAGES}" == "true" ]]; then
  echo
  echo "Docker image selected for local cache removal if present:"
  echo "  ${DHI_IMAGE_REF:-<not detected>}"
fi

if [[ "${PRUNE_CONTAINERS}" == "true" ]]; then
  echo
  echo "Docker containers selected for stop/remove:"
  echo "  all containers on this host"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  log "Dry run complete. Nothing removed."
  exit 0
fi

if [[ "${ASSUME_YES}" != "true" ]]; then
  echo
  read -r -p "Proceed with cleanup? Type 'purge' to continue: " confirmation
  if [[ "${confirmation}" != "purge" ]]; then
    echo "Cleanup cancelled."
    exit 0
  fi
fi

if [[ ${#paths_to_remove[@]} -gt 0 ]]; then
  log "Removing downloaded/generated bundle artifacts"
  rm -rf -- "${paths_to_remove[@]}"
fi

# Recreate expected staging directories so follow-on scripts do not care whether they existed.
mkdir -p \
  "${BUNDLE_DIR}/output" \
  "${BUNDLE_DIR}/packages/docker-debs" \
  "${BUNDLE_DIR}/installers" \
  "${BUNDLE_DIR}/images" \
  "${BUNDLE_DIR}/sbom" \
  "${BUNDLE_DIR}/certs"

if [[ "${PURGE_DOCKER_IMAGES}" == "true" ]]; then
  if command -v docker >/dev/null 2>&1 && [[ -n "${DHI_IMAGE_REF}" ]]; then
    log "Removing local Docker image cache entry for ${DHI_IMAGE_REF}, if present"
    docker image rm "${DHI_IMAGE_REF}" >/dev/null 2>&1 || warn "Docker image was not present or could not be removed: ${DHI_IMAGE_REF}"
  elif [[ -z "${DHI_IMAGE_REF}" ]]; then
    warn "No DHI image reference detected; skipping Docker image cache cleanup."
  else
    warn "Docker CLI not found; skipping Docker image cache cleanup."
  fi
fi

if [[ "${PURGE_DOCKER_AUTH}" == "true" ]]; then
  log "Removing Docker auth files left by older staging runs, if present"
  rm -f /root/.docker/config.json
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    user_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
    if [[ -n "${user_home}" ]]; then
      rm -f "${user_home}/.docker/config.json"
    fi
  fi
fi

if [[ "${PRUNE_CONTAINERS}" == "true" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker CLI not found; skipping container prune."
  else
    mapfile -t container_ids < <(docker ps -aq)
    if [[ ${#container_ids[@]} -eq 0 ]]; then
      log "No Docker containers found to stop/remove."
    else
      log "Stopping and removing all Docker containers"
      docker rm -f "${container_ids[@]}" >/dev/null 2>&1 || warn "One or more containers could not be removed."
    fi
  fi
fi

log "Clean slate complete."
echo "Next staging run: sudo ./tools/download-airgap-artifacts-on-internet-host.sh"
