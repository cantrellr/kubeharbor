#!/usr/bin/env bash
set -euo pipefail

# Generate SBOM/provenance files for the kubeharbor air-gap payload.
#
# This script is intended to run on the Internet-connected staging host before
# tools/download-airgap-artifacts-on-internet-host.sh creates the moveable .tgz.
# The generated sbom/ directory is included inside the air-gap tarball and can
# also be archived next to the tarball for external transfer records.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
SBOM_DIR=""
PACKAGE_NAME="kubeharbor-airgap"
HARBOR_VERSION=""
DHI_IMAGE=""
INSTALL_SYFT="false"
REQUIRE_SYFT="false"

usage() {
  cat <<USAGE
Usage: ./tools/generate-airgap-sbom.sh [options]

Generates file-level SBOM and provenance metadata for the kubeharbor air-gap
payload before it is compressed and moved into the air-gapped environment.

Options:
  --repo PATH                 Repository/bundle root. Default: repo parent of this script.
  --output-dir PATH           SBOM output directory. Default: <repo>/sbom.
  --package-name NAME         Air-gap package basename used for metadata.
  --harbor-version VERSION    Harbor version included in the bundle.
  --dhi-image IMAGE           DHI image reference saved into the bundle.
  --install-syft              Install syft to /usr/local/bin if it is missing.
  --require-syft              Fail if syft is unavailable or syft export generation fails.
  -h, --help                  Show this help.

Outputs:
  sbom/airgap-bundle-manifest.json       File inventory and provenance metadata.
  sbom/airgap-bundle.spdx.json           Built-in SPDX 2.3 file-level SBOM.
  sbom/airgap-bundle.cyclonedx.json      Built-in CycloneDX 1.5 file-level SBOM.
  sbom/syft-spdx.json                    Optional syft-generated SPDX SBOM.
  sbom/syft-cyclonedx.json               Optional syft-generated CycloneDX SBOM.
  sbom/airgap-bundle-summary.txt         Human-readable summary.
  sbom/SHA256SUMS                        Checksums for generated SBOM artifacts.

Notes:
  - The SBOM describes the payload before compression.
  - Private keys, output tarballs, Docker credentials, .git, and generated SBOM
    files are intentionally excluded from the analyzed payload.
USAGE
}

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }
err() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || err "missing command: $1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || err "--repo requires a path"
      REPO_DIR="$(cd "$2" && pwd -P)"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || err "--output-dir requires a path"
      SBOM_DIR="$2"
      shift 2
      ;;
    --package-name)
      [[ $# -ge 2 ]] || err "--package-name requires a value"
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --harbor-version)
      [[ $# -ge 2 ]] || err "--harbor-version requires a value"
      HARBOR_VERSION="$2"
      shift 2
      ;;
    --dhi-image)
      [[ $# -ge 2 ]] || err "--dhi-image requires a value"
      DHI_IMAGE="$2"
      shift 2
      ;;
    --install-syft)
      INSTALL_SYFT="true"
      shift
      ;;
    --require-syft)
      REQUIRE_SYFT="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      ;;
  esac
done

SBOM_DIR="${SBOM_DIR:-${REPO_DIR}/sbom}"
SBOM_DIR="$(mkdir -p "$SBOM_DIR" && cd "$SBOM_DIR" && pwd -P)"

need_cmd python3
need_cmd sha256sum

if [[ ! -d "$REPO_DIR/tools" || ! -f "$REPO_DIR/tools/download-airgap-artifacts-on-internet-host.sh" ]]; then
  err "--repo does not look like the kubeharbor repository root: ${REPO_DIR}"
fi

install_syft() {
  need_cmd curl
  if [[ $EUID -ne 0 ]]; then
    err "--install-syft requires root because it installs to /usr/local/bin. Run the parent staging script with sudo or install syft yourself."
  fi
  log "Installing syft to /usr/local/bin"
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
}

if ! command -v syft >/dev/null 2>&1 && [[ "$INSTALL_SYFT" == "true" ]]; then
  install_syft
fi

if ! command -v syft >/dev/null 2>&1 && [[ "$REQUIRE_SYFT" == "true" ]]; then
  err "syft is required but is not installed. Re-run with --install-syft or install syft before generating the package."
fi

log "Generating air-gap payload SBOM"
log "Repository: ${REPO_DIR}"
log "SBOM dir:   ${SBOM_DIR}"

# Remove generated SBOM files from prior runs while preserving the committed README.
find "$SBOM_DIR" -mindepth 1 -maxdepth 1 -type f ! -name README.md -delete

GIT_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="unknown"
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$REPO_DIR" diff --quiet --ignore-submodules -- && git -C "$REPO_DIR" diff --cached --quiet --ignore-submodules --; then
    GIT_DIRTY="false"
  else
    GIT_DIRTY="true"
  fi
fi

export REPO_DIR SBOM_DIR PACKAGE_NAME HARBOR_VERSION DHI_IMAGE GIT_COMMIT GIT_DIRTY

python3 <<'PY'
import datetime as dt
import hashlib
import json
import os
import platform
import re
import stat
import uuid
from pathlib import Path

repo = Path(os.environ["REPO_DIR"]).resolve()
sbom_dir = Path(os.environ["SBOM_DIR"]).resolve()
package_name = os.environ.get("PACKAGE_NAME", "kubeharbor-airgap")
harbor_version = os.environ.get("HARBOR_VERSION", "")
dhi_image = os.environ.get("DHI_IMAGE", "")
git_commit = os.environ.get("GIT_COMMIT", "unknown")
git_dirty = os.environ.get("GIT_DIRTY", "unknown")
generated_at = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

excluded_prefixes = (
    ".git/",
    ".docker/",
    ".diagram-tools/",
    "diagrams/node_modules/",
    "output/",
    "sbom/",
)
excluded_exact = {
    ".diagram-sync-updated-files.txt",
}
excluded_patterns = (
    re.compile(r"^certs/.*\.key$"),
    re.compile(r"^certs/.*\.srl$"),
    re.compile(r"^certs/.*\.csr$"),
    re.compile(r"(^|/)\.DS_Store$"),
    re.compile(r"(^|/)Thumbs\.db$"),
    re.compile(r".*\.tmp$"),
    re.compile(r".*\.swp$"),
)

def rel_path(path: Path) -> str:
    return path.relative_to(repo).as_posix()

def excluded(rel: str) -> bool:
    if rel in excluded_exact:
        return True
    if any(rel.startswith(prefix) for prefix in excluded_prefixes):
        return True
    return any(pattern.match(rel) for pattern in excluded_patterns)

def sha(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm.lower().replace("-", ""))
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def category(rel: str) -> str:
    if rel.startswith("packages/docker-debs/"):
        return "docker-offline-packages"
    if rel.startswith("installers/"):
        return "harbor-offline-installer"
    if rel.startswith("images/"):
        return "saved-container-images"
    if rel.startswith("config/"):
        return "configuration"
    if rel.startswith("scripts/"):
        return "install-runtime-scripts"
    if rel.startswith("tools/"):
        return "staging-and-transfer-tools"
    if rel.startswith("systemd/"):
        return "systemd-units"
    if rel.startswith("docs/"):
        return "documentation"
    if rel.startswith("diagrams/"):
        return "documentation-diagrams"
    if rel.startswith("certs/"):
        return "certificate-public-material"
    return "repository-content"

files = []
for path in sorted(repo.rglob("*")):
    try:
        rel = rel_path(path)
    except ValueError:
        continue
    if excluded(rel):
        continue
    try:
        st = path.lstat()
    except OSError:
        continue
    if path.is_dir():
        continue
    if stat.S_ISREG(st.st_mode):
        files.append({
            "path": rel,
            "type": "file",
            "size_bytes": st.st_size,
            "mode": oct(st.st_mode & 0o777),
            "sha256": sha(path, "sha256"),
            "sha1": sha(path, "sha1"),
            "category": category(rel),
        })
    elif path.is_symlink():
        files.append({
            "path": rel,
            "type": "symlink",
            "target": os.readlink(path),
            "size_bytes": st.st_size,
            "mode": oct(st.st_mode & 0o777),
            "category": category(rel),
        })

category_counts = {}
category_bytes = {}
for f in files:
    cat = f["category"]
    category_counts[cat] = category_counts.get(cat, 0) + 1
    category_bytes[cat] = category_bytes.get(cat, 0) + int(f.get("size_bytes", 0))

manifest = {
    "schema": "kubeharbor.airgap.bundle.sbom/v1",
    "package_name": package_name,
    "generated_at": generated_at,
    "generator": "tools/generate-airgap-sbom.sh",
    "repository": "cantrellr/kubeharbor",
    "git": {
        "commit": git_commit,
        "dirty": git_dirty,
    },
    "target": {
        "os": "Ubuntu 24.04 LTS amd64",
        "harbor_version": harbor_version,
        "dhi_image": dhi_image,
    },
    "scope": {
        "description": "File-level inventory for the kubeharbor air-gap payload before compression.",
        "included_root": str(repo),
        "excluded": [
            ".git/",
            ".docker/",
            ".diagram-tools/",
            "diagrams/node_modules/",
            "output/",
            "sbom/",
            "certs/*.key",
            "certs/*.srl",
            "certs/*.csr",
            "local editor/cache files",
        ],
    },
    "environment": {
        "hostname": platform.node(),
        "platform": platform.platform(),
        "python": platform.python_version(),
    },
    "summary": {
        "file_count": len(files),
        "total_size_bytes": sum(int(f.get("size_bytes", 0)) for f in files),
        "category_counts": category_counts,
        "category_size_bytes": category_bytes,
    },
    "files": files,
}

(sbom_dir / "airgap-bundle-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=False) + "\n", encoding="utf-8")

def spdx_id_for(rel: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9.-]+", "-", rel).strip("-")
    if not safe:
        safe = "root"
    return "SPDXRef-File-" + safe[:180]

file_spdx_ids = {}
spdx_files = []
sha1s = []
for f in files:
    if f.get("type") != "file":
        continue
    sid = spdx_id_for(f["path"])
    base = sid
    idx = 2
    while sid in file_spdx_ids.values():
        sid = f"{base}-{idx}"
        idx += 1
    file_spdx_ids[f["path"]] = sid
    sha1s.append(f["sha1"])
    spdx_files.append({
        "SPDXID": sid,
        "fileName": f"./{f['path']}",
        "checksums": [
            {"algorithm": "SHA1", "checksumValue": f["sha1"]},
            {"algorithm": "SHA256", "checksumValue": f["sha256"]},
        ],
        "fileTypes": ["OTHER"],
        "licenseConcluded": "NOASSERTION",
        "licenseInfoInFiles": ["NOASSERTION"],
        "copyrightText": "NOASSERTION",
    })

verification_code = hashlib.sha1("".join(sorted(sha1s)).encode("utf-8")).hexdigest() if sha1s else hashlib.sha1(b"").hexdigest()
document_namespace = f"https://github.com/cantrellr/kubeharbor/sbom/{package_name}/{uuid.uuid4()}"

spdx = {
    "spdxVersion": "SPDX-2.3",
    "dataLicense": "CC0-1.0",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": f"{package_name} air-gap payload",
    "documentNamespace": document_namespace,
    "creationInfo": {
        "created": generated_at,
        "creators": [
            "Tool: kubeharbor generate-airgap-sbom.sh",
            "Organization: cantrellr",
        ],
    },
    "packages": [
        {
            "name": package_name,
            "SPDXID": "SPDXRef-Package-kubeharbor-airgap-payload",
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": True,
            "packageVerificationCode": {
                "packageVerificationCodeValue": verification_code
            },
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        }
    ],
    "files": spdx_files,
    "relationships": [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": "SPDXRef-Package-kubeharbor-airgap-payload",
        }
    ] + [
        {
            "spdxElementId": "SPDXRef-Package-kubeharbor-airgap-payload",
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": file_spdx_ids[f["path"]],
        }
        for f in files if f.get("type") == "file"
    ],
}
(sbom_dir / "airgap-bundle.spdx.json").write_text(json.dumps(spdx, indent=2, sort_keys=False) + "\n", encoding="utf-8")

cyclonedx = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{uuid.uuid4()}",
    "version": 1,
    "metadata": {
        "timestamp": generated_at,
        "tools": {
            "components": [
                {
                    "type": "application",
                    "name": "kubeharbor generate-airgap-sbom.sh",
                    "version": "1",
                }
            ]
        },
        "component": {
            "type": "application",
            "name": package_name,
            "version": harbor_version or "unknown",
            "bom-ref": "pkg:kubeharbor-airgap-payload",
            "properties": [
                {"name": "git.commit", "value": git_commit},
                {"name": "git.dirty", "value": git_dirty},
                {"name": "dhi.image", "value": dhi_image},
            ],
        },
    },
    "components": [
        {
            "type": "file",
            "name": f["path"],
            "bom-ref": f"file:{f['path']}",
            "hashes": [
                {"alg": "SHA-1", "content": f["sha1"]},
                {"alg": "SHA-256", "content": f["sha256"]},
            ],
            "properties": [
                {"name": "kubeharbor.category", "value": f["category"]},
                {"name": "kubeharbor.size_bytes", "value": str(f["size_bytes"])},
            ],
        }
        for f in files if f.get("type") == "file"
    ],
}
(sbom_dir / "airgap-bundle.cyclonedx.json").write_text(json.dumps(cyclonedx, indent=2, sort_keys=False) + "\n", encoding="utf-8")

summary = [
    "kubeharbor air-gap payload SBOM summary",
    f"Generated: {generated_at}",
    f"Package name: {package_name}",
    f"Harbor version: {harbor_version or 'unknown'}",
    f"DHI image: {dhi_image or 'not included'}",
    f"Git commit: {git_commit}",
    f"Git dirty: {git_dirty}",
    f"Files inventoried: {len(files)}",
    f"Total bytes: {manifest['summary']['total_size_bytes']}",
    "",
    "Category counts:",
]
for cat in sorted(category_counts):
    summary.append(f"  - {cat}: {category_counts[cat]} file(s), {category_bytes.get(cat, 0)} byte(s)")
summary.extend([
    "",
    "Generated files:",
    "  - airgap-bundle-manifest.json",
    "  - airgap-bundle.spdx.json",
    "  - airgap-bundle.cyclonedx.json",
    "",
    "Scope exclusions:",
    "  - .git/",
    "  - .docker/",
    "  - output/",
    "  - sbom/",
    "  - certs/*.key",
    "  - local diagram tooling/cache directories",
])
(sbom_dir / "airgap-bundle-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
PY

run_syft_exports() {
  # Current Syft versions reject absolute exclude paths for directory sources.
  # Keep these relative to the dir: source root and prefix them with ./ per Syft's matcher contract.
  local syft_excludes=(
    --exclude './.git'
    --exclude './.git/**'
    --exclude './.docker'
    --exclude './.docker/**'
    --exclude './.diagram-tools'
    --exclude './.diagram-tools/**'
    --exclude './diagrams/node_modules'
    --exclude './diagrams/node_modules/**'
    --exclude './output'
    --exclude './output/**'
    --exclude './sbom'
    --exclude './sbom/**'
    --exclude './certs/*.key'
    --exclude './certs/*.srl'
    --exclude './certs/*.csr'
  )

  syft "dir:${REPO_DIR}" "${syft_excludes[@]}" -o "spdx-json=${SBOM_DIR}/syft-spdx.json"
  syft "dir:${REPO_DIR}" "${syft_excludes[@]}" -o "cyclonedx-json=${SBOM_DIR}/syft-cyclonedx.json"
}

if command -v syft >/dev/null 2>&1; then
  log "Generating optional syft SBOM exports"
  if ! run_syft_exports; then
    if [[ "$REQUIRE_SYFT" == "true" ]]; then
      err "syft SBOM export generation failed. Built-in SBOM files were generated, but --require-syft requires successful syft exports."
    fi
    warn "syft SBOM export generation failed. Continuing with built-in file-level SPDX/CycloneDX SBOMs."
    rm -f "${SBOM_DIR}/syft-spdx.json" "${SBOM_DIR}/syft-cyclonedx.json"
  fi
else
  warn "syft not found. Built-in file-level SPDX/CycloneDX SBOMs were generated; install syft for richer package/component discovery."
fi

(
  cd "$SBOM_DIR"
  find . -maxdepth 1 -type f ! -name README.md ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 sha256sum > SHA256SUMS
)

log "SBOM generation complete"
echo "Generated files:"
find "$SBOM_DIR" -maxdepth 1 -type f | sort | sed 's#^#  #'
