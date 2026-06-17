#!/usr/bin/env bash
set -euo pipefail

HARBOR_DIR="${HARBOR_DIR:-/opt/harbor}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/data/docker}"
ASSUME_YES="false"
DRY_RUN="false"
REMOVE_VOLUMES="false"

usage() {
  cat <<USAGE
Usage: sudo /usr/local/sbin/harbor-reset.sh [options]

Cleans Harbor deployment runtime state while preserving local Docker images and
preserving Harbor data under /data.

Default behavior:
  - Runs 'docker compose down' in Harbor install directory.
  - Does NOT remove local Docker images.
  - Does NOT remove Harbor compose volumes or Harbor data on disk.
  - Does NOT remove /data/database unless --remove-volumes is set.

Options:
  -y, --yes   Do not prompt for confirmation.
      --dry-run
              Print the actions that would run without making changes.
      --remove-volumes
        Also remove Harbor Docker Compose volumes (docker compose down -v).
  -h, --help  Show this help.

Environment:
  HARBOR_DIR  Harbor compose directory (default: /opt/harbor)
  DOCKER_DATA_ROOT  Docker data-root directory (default: /data/docker)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES="true" ;;
    --dry-run) DRY_RUN="true" ;;
    --remove-volumes) REMOVE_VOLUMES="true" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

log() { echo "==> $*"; }

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker CLI is required." >&2
  exit 1
fi

if [[ ! -d "${HARBOR_DIR}" ]]; then
  echo "ERROR: Harbor directory not found: ${HARBOR_DIR}" >&2
  exit 1
fi

compose_file=""
for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  if [[ -f "${HARBOR_DIR}/${candidate}" ]]; then
    compose_file="${candidate}"
    break
  fi
done

if [[ -z "${compose_file}" ]]; then
  echo "ERROR: no Docker Compose file found in ${HARBOR_DIR}" >&2
  exit 1
fi

cat <<SUMMARY
Harbor runtime reset request
Harbor directory:      ${HARBOR_DIR}
Compose file:          ${compose_file}
Dry run:               ${DRY_RUN}
Preserve local images: true
Preserve /data:        true
Remove compose volumes:${REMOVE_VOLUMES}
Remove database dir:    ${REMOVE_VOLUMES}
SUMMARY

if [[ "${DRY_RUN}" == "true" ]]; then
  down_args=("down")
  if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
    down_args+=("-v")
  fi

  echo ""
  echo "Planned command:"
  echo "  cd ${HARBOR_DIR}"
  echo "  docker compose ${down_args[*]}"
  if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
    echo "  rm -rf /data/database"
  fi
  log "Dry run complete. Nothing changed."
  exit 0
fi

if [[ "${ASSUME_YES}" != "true" ]]; then
  echo ""
  read -r -p "Proceed with Harbor runtime reset? Type 'reset' to continue: " confirmation
  if [[ "${confirmation}" != "reset" ]]; then
    echo "Reset cancelled."
    exit 0
  fi
fi

cd "${HARBOR_DIR}"
down_args=("down")
if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
  down_args+=("-v")
  log "Stopping Harbor and removing compose resources (containers/networks/volumes)"
else
  log "Stopping Harbor and removing compose resources (containers/networks)"
fi
docker compose "${down_args[@]}"

if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
  if [[ -d "/data/database" ]]; then
    log "Removing Docker database directory /data/database"
    rm -rf -- "/data/database"
  else
    log "Docker database directory /data/database was not present"
  fi
fi

log "Harbor runtime reset complete. Local Docker images and /data were preserved."