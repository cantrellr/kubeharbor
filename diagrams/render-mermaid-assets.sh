#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$(pwd)}"
REPO_DIR="$(cd "${REPO_DIR}" && pwd)"
SOURCE_DIR="${REPO_DIR}/diagrams/mermaid-source"
SVG_DIR="${REPO_DIR}/diagrams/svg"
PNG_DIR="${REPO_DIR}/diagrams/png"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "ERROR: Mermaid source directory not found: ${SOURCE_DIR}" >&2
  exit 1
fi

mkdir -p "${SVG_DIR}" "${PNG_DIR}"

if command -v mmdc >/dev/null 2>&1; then
  MMDC=(mmdc)
elif command -v npx >/dev/null 2>&1; then
  MMDC=(npx --yes @mermaid-js/mermaid-cli)
else
  echo "ERROR: Mermaid CLI is required. Install @mermaid-js/mermaid-cli or make mmdc available on PATH." >&2
  exit 1
fi

PUPPETEER_ARGS=()
if [[ -n "${PUPPETEER_CONFIG:-}" ]]; then
  PUPPETEER_ARGS=(-p "${PUPPETEER_CONFIG}")
fi

for source_file in "${SOURCE_DIR}"/*.mmd; do
  [[ -e "${source_file}" ]] || continue
  base_name="$(basename "${source_file}" .mmd)"
  svg_file="${SVG_DIR}/${base_name}.svg"
  png_file="${PNG_DIR}/${base_name}.png"

  echo "Rendering ${base_name}.svg"
  "${MMDC[@]}" "${PUPPETEER_ARGS[@]}" -i "${source_file}" -o "${svg_file}" -b transparent

  echo "Rendering ${base_name}.png"
  "${MMDC[@]}" "${PUPPETEER_ARGS[@]}" -i "${source_file}" -o "${png_file}" -b transparent -s 2
done

python3 - <<'PY' "${PNG_DIR}"
from pathlib import Path
from PIL import Image
import sys

png_dir = Path(sys.argv[1])
try:
    for path in sorted(png_dir.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        background = Image.new("RGBA", image.size, (255, 255, 255, 255))
        background.alpha_composite(image)
        optimized = background.convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT)
        optimized.save(path, optimize=True)
except Exception as exc:
    print(f"WARNING: PNG optimization skipped: {exc}", file=sys.stderr)
PY

echo "Mermaid SVG/PNG export rendering complete."
