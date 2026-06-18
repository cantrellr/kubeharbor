#!/usr/bin/env bash
set -euo pipefail

# Render Mermaid source diagrams into checked-in SVG and PNG exports.
#
# Source of truth:
#   diagrams/mermaid-source/*.mmd
#
# Generated outputs:
#   diagrams/svg/*.svg
#   diagrams/png/*.png
#
# Usage examples:
#   ./diagrams/render-mermaid-assets.sh --repo .
#   ./diagrams/render-mermaid-assets.sh --repo . --install-deps
#   ./diagrams/render-mermaid-assets.sh --repo . --sync-index
#   ./diagrams/render-mermaid-assets.sh --repo . --theme default --background transparent --scale 2
#
# This script is intentionally local-first. It does not require GitHub Actions.

usage() {
  cat <<'EOF'
Usage:
  ./diagrams/render-mermaid-assets.sh [options] [repo-path]

Options:
  --repo PATH              Path to the local kubeharbor repo clone. Defaults to repo root inferred from this script.
  --install-deps           Install Mermaid CLI locally under .diagram-tools/ using npm.
  --sync-index             Run diagrams/sync-mermaid-markdown.py after rendering.
  --clean                  Delete existing SVG/PNG exports before rendering.
  --theme NAME             Mermaid theme for exports. Default: default.
  --background VALUE       SVG/PNG background. Default: transparent.
  --scale VALUE            PNG render scale. Default: 2.
  --config PATH            Optional Mermaid config JSON file.
  --puppeteer-config PATH  Optional Puppeteer config JSON file. Defaults to diagrams/puppeteer-config.json when present.
  --help                   Show this help.

Dependency model:
  1. Uses .diagram-tools/node_modules/.bin/mmdc when present.
  2. Uses diagrams/node_modules/.bin/mmdc when present.
  3. Uses mmdc from PATH when present.
  4. With --install-deps, installs @mermaid-js/mermaid-cli locally under .diagram-tools/.

No GitHub Actions are required.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFERRED_REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPO_DIR=""
INSTALL_DEPS=0
SYNC_INDEX=0
CLEAN=0
THEME="${MERMAID_THEME:-default}"
BACKGROUND="${MERMAID_BACKGROUND:-transparent}"
PNG_SCALE="${MERMAID_SCALE:-2}"
MERMAID_CONFIG_FILE="${MERMAID_CONFIG_FILE:-}"
PUPPETEER_CONFIG_FILE="${PUPPETEER_CONFIG:-}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_DIR="${2:-}"
      shift 2
      ;;
    --install-deps)
      INSTALL_DEPS=1
      shift
      ;;
    --sync-index)
      SYNC_INDEX=1
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --theme)
      THEME="${2:-}"
      shift 2
      ;;
    --background)
      BACKGROUND="${2:-}"
      shift 2
      ;;
    --scale)
      PNG_SCALE="${2:-}"
      shift 2
      ;;
    --config)
      MERMAID_CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --puppeteer-config)
      PUPPETEER_CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${REPO_DIR}" && ${#POSITIONAL[@]} -gt 0 ]]; then
  REPO_DIR="${POSITIONAL[0]}"
fi
if [[ -z "${REPO_DIR}" ]]; then
  REPO_DIR="${INFERRED_REPO_DIR}"
fi

REPO_DIR="$(cd "${REPO_DIR}" && pwd)"
SOURCE_DIR="${REPO_DIR}/diagrams/mermaid-source"
SVG_DIR="${REPO_DIR}/diagrams/svg"
PNG_DIR="${REPO_DIR}/diagrams/png"
TOOLS_DIR="${REPO_DIR}/.diagram-tools"
DEFAULT_PUPPETEER_CONFIG="${REPO_DIR}/diagrams/puppeteer-config.json"

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "ERROR: Repo path does not look like a Git clone: ${REPO_DIR}" >&2
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "ERROR: Mermaid source directory not found: ${SOURCE_DIR}" >&2
  exit 1
fi

if ! [[ "${PNG_SCALE}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "ERROR: --scale must be numeric. Got: ${PNG_SCALE}" >&2
  exit 1
fi

if [[ -n "${MERMAID_CONFIG_FILE}" ]]; then
  MERMAID_CONFIG_FILE="$(cd "$(dirname "${MERMAID_CONFIG_FILE}")" && pwd)/$(basename "${MERMAID_CONFIG_FILE}")"
  if [[ ! -f "${MERMAID_CONFIG_FILE}" ]]; then
    echo "ERROR: Mermaid config file not found: ${MERMAID_CONFIG_FILE}" >&2
    exit 1
  fi
fi

if [[ -z "${PUPPETEER_CONFIG_FILE}" && -f "${DEFAULT_PUPPETEER_CONFIG}" ]]; then
  PUPPETEER_CONFIG_FILE="${DEFAULT_PUPPETEER_CONFIG}"
fi
if [[ -n "${PUPPETEER_CONFIG_FILE}" ]]; then
  PUPPETEER_CONFIG_FILE="$(cd "$(dirname "${PUPPETEER_CONFIG_FILE}")" && pwd)/$(basename "${PUPPETEER_CONFIG_FILE}")"
  if [[ ! -f "${PUPPETEER_CONFIG_FILE}" ]]; then
    echo "ERROR: Puppeteer config file not found: ${PUPPETEER_CONFIG_FILE}" >&2
    exit 1
  fi
fi

mkdir -p "${SVG_DIR}" "${PNG_DIR}"

install_local_mermaid_cli() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm is required for --install-deps." >&2
    echo "Install Node.js/npm first, or install Mermaid CLI globally with: npm install -g @mermaid-js/mermaid-cli" >&2
    exit 1
  fi

  mkdir -p "${TOOLS_DIR}"
  cat > "${TOOLS_DIR}/package.json" <<'EOF'
{
  "private": true,
  "description": "Local Mermaid CLI tooling for kubeharbor diagram exports",
  "devDependencies": {
    "@mermaid-js/mermaid-cli": "latest"
  }
}
EOF

  echo "Installing Mermaid CLI locally under ${TOOLS_DIR} ..."
  npm install --prefix "${TOOLS_DIR}" --no-audit --no-fund
}

find_mmdc() {
  if [[ -x "${TOOLS_DIR}/node_modules/.bin/mmdc" ]]; then
    printf '%s\n' "${TOOLS_DIR}/node_modules/.bin/mmdc"
    return 0
  fi

  if [[ -x "${REPO_DIR}/diagrams/node_modules/.bin/mmdc" ]]; then
    printf '%s\n' "${REPO_DIR}/diagrams/node_modules/.bin/mmdc"
    return 0
  fi

  if command -v mmdc >/dev/null 2>&1; then
    command -v mmdc
    return 0
  fi

  return 1
}

if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
  install_local_mermaid_cli
fi

if ! MMDC_BIN="$(find_mmdc)"; then
  cat >&2 <<'EOF'
ERROR: Mermaid CLI executable 'mmdc' was not found.

Fix options:
  1. Let this repo install local tooling:
       ./diagrams/render-mermaid-assets.sh --repo . --install-deps

  2. Install Mermaid CLI globally:
       npm install -g @mermaid-js/mermaid-cli

  3. Add an existing mmdc binary to PATH and rerun this script.

GitHub Actions are not required.
EOF
  exit 1
fi

if [[ "${CLEAN}" -eq 1 ]]; then
  echo "Cleaning existing diagram exports ..."
  find "${SVG_DIR}" -maxdepth 1 -type f -name '*.svg' -delete
  find "${PNG_DIR}" -maxdepth 1 -type f -name '*.png' -delete
fi

COMMON_ARGS=(--theme "${THEME}" --backgroundColor "${BACKGROUND}")
if [[ -n "${MERMAID_CONFIG_FILE}" ]]; then
  COMMON_ARGS+=(--configFile "${MERMAID_CONFIG_FILE}")
fi
if [[ -n "${PUPPETEER_CONFIG_FILE}" ]]; then
  COMMON_ARGS+=(--puppeteerConfigFile "${PUPPETEER_CONFIG_FILE}")
fi

shopt -s nullglob
SOURCE_FILES=("${SOURCE_DIR}"/*.mmd)
if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No Mermaid .mmd files found in ${SOURCE_DIR}" >&2
  exit 1
fi

printf 'Rendering %s Mermaid diagram(s) from %s\n' "${#SOURCE_FILES[@]}" "${SOURCE_DIR}"
printf 'Renderer: %s\n' "${MMDC_BIN}"
printf 'Theme: %s | Background: %s | PNG scale: %s\n' "${THEME}" "${BACKGROUND}" "${PNG_SCALE}"

for source_file in "${SOURCE_FILES[@]}"; do
  base_name="$(basename "${source_file}" .mmd)"
  svg_file="${SVG_DIR}/${base_name}.svg"
  png_file="${PNG_DIR}/${base_name}.png"

  echo "Rendering ${base_name}.svg"
  "${MMDC_BIN}" -i "${source_file}" -o "${svg_file}" "${COMMON_ARGS[@]}"

  echo "Rendering ${base_name}.png"
  "${MMDC_BIN}" -i "${source_file}" -o "${png_file}" "${COMMON_ARGS[@]}" --scale "${PNG_SCALE}"

  if ! grep -qi '<svg' "${svg_file}"; then
    echo "ERROR: Rendered SVG does not look valid: ${svg_file}" >&2
    exit 1
  fi

  if ! python3 - "${png_file}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
with path.open('rb') as handle:
    header = handle.read(8)
if header != b'\x89PNG\r\n\x1a\n':
    raise SystemExit(1)
PY
  then
    echo "ERROR: Rendered PNG does not look valid: ${png_file}" >&2
    exit 1
  fi
done

if [[ "${SYNC_INDEX}" -eq 1 ]]; then
  if [[ ! -f "${REPO_DIR}/diagrams/sync-mermaid-markdown.py" ]]; then
    echo "ERROR: Cannot sync index; missing diagrams/sync-mermaid-markdown.py" >&2
    exit 1
  fi
  python3 "${REPO_DIR}/diagrams/sync-mermaid-markdown.py" "${REPO_DIR}"
fi

cat <<EOF

Mermaid SVG/PNG export rendering complete.

Updated folders:
  ${SVG_DIR}
  ${PNG_DIR}

Review changes:
  git -C "${REPO_DIR}" status --short
EOF
