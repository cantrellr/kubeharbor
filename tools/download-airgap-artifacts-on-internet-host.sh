#!/usr/bin/env bash
set -euo pipefail

# Run this on an Internet-connected Ubuntu 24.04 x86_64 staging machine.
# It downloads Docker Engine offline packages, Harbor's offline installer,
# pulls/saves the requested DHI image, generates SBOM/provenance metadata,
# and emits a single tarball to move into the air gap.

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARBOR_VERSION="${HARBOR_VERSION:-v2.15.1}"
# Default to the runtime Docker Hardened Image tag. Use the -dev tag only for build/debug workflows.
DHI_IMAGE="${DHI_IMAGE:-cantrellcloud/dhi-harbor-portal:2.15.1-debian}"
DOWNLOAD_HARBOR="${DOWNLOAD_HARBOR:-true}"
DOWNLOAD_DOCKER_DEBS="${DOWNLOAD_DOCKER_DEBS:-true}"
DOWNLOAD_DHI_IMAGE="${DOWNLOAD_DHI_IMAGE:-true}"
GENERATE_SBOM="${GENERATE_SBOM:-true}"
INSTALL_SYFT_FOR_SBOM="${INSTALL_SYFT_FOR_SBOM:-false}"
REQUIRE_SYFT_FOR_SBOM="${REQUIRE_SYFT_FOR_SBOM:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-${BUNDLE_DIR}/output}"
PACKAGE_BASENAME="${PACKAGE_BASENAME:-kubeharbor-airgap-${HARBOR_VERSION}-$(date +%Y%m%d-%H%M%S)}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root on the staging machine: sudo $0" >&2
  exit 1
fi

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
err() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || err "missing command: $1"; }

mkdir -p "${BUNDLE_DIR}/packages/docker-debs" "${BUNDLE_DIR}/installers" "${BUNDLE_DIR}/images" "${BUNDLE_DIR}/sbom" "${OUTPUT_DIR}"

. /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  warn "staging host is ${PRETTY_NAME}; target package set is intended for Ubuntu 24.04."
fi
if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
  err "this script currently expects amd64/x86_64, matching the kubeharbor VM."
fi

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release apt-transport-https apt-rdepends
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update

if [[ "${DOWNLOAD_DOCKER_DEBS}" == "true" ]]; then
  log "Downloading Docker Engine packages and dependency .debs for offline install"
  rm -rf /tmp/kubeharbor-docker-debs
  mkdir -p /tmp/kubeharbor-docker-debs
  chmod 0777 /tmp/kubeharbor-docker-debs
  pushd /tmp/kubeharbor-docker-debs >/dev/null

  core_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  mapfile -t all_packages < <(
    apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "${core_packages[@]}" |
      awk '/^[[:alnum:]][[:alnum:].+:-]+$/ {print $1}' |
      sed 's/:amd64$//' |
      sort -u
  )
  printf '%s\n' "${all_packages[@]}" > DOCKER_PACKAGE_LIST.txt

  for pkg in "${all_packages[@]}"; do
    apt-get download "$pkg" || warn "could not download package ${pkg}; it may be virtual or architecture-specific."
  done

  cp -v ./*.deb "${BUNDLE_DIR}/packages/docker-debs/"
  cp -v DOCKER_PACKAGE_LIST.txt "${BUNDLE_DIR}/packages/docker-debs/"
  popd >/dev/null
  rm -rf /tmp/kubeharbor-docker-debs
fi

# Ensure the staging host can pull/save images. Installing Docker here is okay because this is the Internet-connected staging host.
if [[ "${DOWNLOAD_DHI_IMAGE}" == "true" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker on staging host so the DHI image can be pulled and saved"
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  else
    systemctl start docker || true
  fi
fi

download_if_exists() {
  local url="$1"
  local dest="$2"
  local label="$3"

  # GitHub release sidecar artifact names changed across Harbor releases. Probe first so missing optional
  # signatures/checksums do not print a scary curl 404 during an otherwise-successful bundle build.
  local http_code
  http_code="$(curl -fsSIL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
  if [[ "$http_code" == "200" || "$http_code" == "302" ]]; then
    log "Downloading ${label}"
    curl -fL "$url" -o "$dest"
    return 0
  fi
  warn "Optional ${label} not found at release URL; continuing without it. URL=${url} HTTP=${http_code:-unreachable}"
  return 1
}

if [[ "${DOWNLOAD_HARBOR}" == "true" ]]; then
  log "Downloading Harbor offline installer ${HARBOR_VERSION}"
  harbor_file="harbor-offline-installer-${HARBOR_VERSION}.tgz"
  harbor_url="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${harbor_file}"
  curl -fL "${harbor_url}" -o "${BUNDLE_DIR}/installers/${harbor_file}"

  # Harbor 2.15+ release artifacts are signed with Cosign. Asset names can vary, so collect any sidecars
  # that exist and always generate local SHA256SUMS for air-gap transfer validation.
  for suffix in .sig .pem .bundle .sha256 .sha256sum .asc; do
    download_if_exists "${harbor_url}${suffix}" "${BUNDLE_DIR}/installers/${harbor_file}${suffix}" "Harbor release sidecar ${harbor_file}${suffix}" || true
  done
fi

if [[ "${DOWNLOAD_DHI_IMAGE}" == "true" ]]; then
  log "Docker login is required to pull the DHI image: ${DHI_IMAGE}"
  if [[ -z "${DOCKER_USERNAME:-}" ]]; then
    read -r -p "Docker username: " DOCKER_USERNAME
  fi
  if [[ -z "${DOCKER_PASSWORD:-}" ]]; then
    read -r -s -p "Docker password or access token: " DOCKER_PASSWORD
    echo
  fi

  # Use an ephemeral Docker credential store so sudo runs do not leave registry credentials in /root/.docker/config.json.
  docker_config_tmp="$(mktemp -d /tmp/kubeharbor-docker-config.XXXXXX)"
  chmod 0700 "${docker_config_tmp}"
  export DOCKER_CONFIG="${docker_config_tmp}"
  cleanup_docker_config() {
    docker logout >/dev/null 2>&1 || true
    rm -rf "${docker_config_tmp}" >/dev/null 2>&1 || true
  }
  trap cleanup_docker_config EXIT

  echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin
  unset DOCKER_PASSWORD

  log "Pulling ${DHI_IMAGE}"
  docker pull "${DHI_IMAGE}"

  image_safe="$(echo "${DHI_IMAGE}" | tr '/:@' '___')"
  image_tar="${BUNDLE_DIR}/images/${image_safe}.tar"
  docker save "${DHI_IMAGE}" -o "${image_tar}"
  docker image inspect "${DHI_IMAGE}" > "${BUNDLE_DIR}/images/${image_safe}.inspect.json"
  echo "${DHI_IMAGE}" > "${BUNDLE_DIR}/images/DHI_IMAGE_REF.txt"
fi

# Checksums and artifact inventory.
if compgen -G "${BUNDLE_DIR}/packages/docker-debs/*.deb" > /dev/null; then
  sha256sum "${BUNDLE_DIR}"/packages/docker-debs/*.deb > "${BUNDLE_DIR}/packages/docker-debs/SHA256SUMS"
fi
if compgen -G "${BUNDLE_DIR}/installers/harbor-offline-installer-*.tgz" > /dev/null; then
  sha256sum "${BUNDLE_DIR}"/installers/harbor-offline-installer-*.tgz > "${BUNDLE_DIR}/installers/SHA256SUMS"
fi
if compgen -G "${BUNDLE_DIR}/images/*.tar" > /dev/null; then
  sha256sum "${BUNDLE_DIR}"/images/*.tar > "${BUNDLE_DIR}/images/SHA256SUMS"
fi

cat > "${BUNDLE_DIR}/ARTIFACTS.txt" <<ARTIFACTS
kubeharbor air-gap artifact inventory
Generated: $(date -Is)
Target OS: Ubuntu 24.04 LTS amd64
Harbor version: ${HARBOR_VERSION}
DHI image: ${DHI_IMAGE}

Docker packages: packages/docker-debs/
Harbor offline installer: installers/
Extra image archives: images/
SBOM and provenance metadata: sbom/
ARTIFACTS

if [[ "${GENERATE_SBOM}" == "true" ]]; then
  log "Generating air-gap payload SBOM and provenance metadata"
  sbom_args=(
    --repo "${BUNDLE_DIR}"
    --output-dir "${BUNDLE_DIR}/sbom"
    --package-name "${PACKAGE_BASENAME}"
    --harbor-version "${HARBOR_VERSION}"
    --dhi-image "${DHI_IMAGE}"
  )
  if [[ "${INSTALL_SYFT_FOR_SBOM}" == "true" ]]; then
    sbom_args+=(--install-syft)
  fi
  if [[ "${REQUIRE_SYFT_FOR_SBOM}" == "true" ]]; then
    sbom_args+=(--require-syft)
  fi
  bash "${BUNDLE_DIR}/tools/generate-airgap-sbom.sh" "${sbom_args[@]}"
else
  warn "GENERATE_SBOM=false. The moveable air-gap tarball will not contain SBOM/provenance metadata."
fi

# Do not package output/ recursively. Do not include local shell history, Docker credentials, or private keys.
package_path="${OUTPUT_DIR}/${PACKAGE_BASENAME}.tgz"
checksum_path="${package_path}.sha256"
sbom_archive_path="${OUTPUT_DIR}/${PACKAGE_BASENAME}-sbom.tgz"
sbom_archive_checksum_path="${sbom_archive_path}.sha256"

log "Creating moveable air-gap tarball: ${package_path}"
parent="$(dirname "${BUNDLE_DIR}")"
name="$(basename "${BUNDLE_DIR}")"
tar -C "$parent" \
  --exclude="${name}/output" \
  --exclude="${name}/.git" \
  --exclude="${name}/certs/*.key" \
  --exclude="${name}/.docker" \
  -czf "$package_path" "$name"
sha256sum "$package_path" > "$checksum_path"

if [[ -d "${BUNDLE_DIR}/sbom" ]] && compgen -G "${BUNDLE_DIR}/sbom/*" > /dev/null; then
  log "Creating external SBOM archive: ${sbom_archive_path}"
  tar -C "${BUNDLE_DIR}" -czf "$sbom_archive_path" sbom
  sha256sum "$sbom_archive_path" > "$sbom_archive_checksum_path"
fi

cat <<DONE

SUCCESS: air-gap bundle package created.
Package:       ${package_path}
SHA256:        ${checksum_path}
SBOM archive:  ${sbom_archive_path}
SBOM SHA256:   ${sbom_archive_checksum_path}

Move the package, package checksum, SBOM archive, and SBOM checksum to the air-gapped VM.
On kubeharbor:
  sha256sum -c $(basename "$checksum_path")
  tar -xzf $(basename "$package_path")
  cd ${name}
  cp /path/to/kubeharbor.dev.kube.crt certs/
  cp /path/to/kubeharbor.dev.kube.key certs/
  cp /path/to/ca.crt certs/
  vi config/harbor.env
  sudo ./install.sh
DONE
