#!/usr/bin/env bash
set -euo pipefail

echo "==> Optional DHI Harbor portal image override"

[[ "${USE_DHI_HARBOR_PORTAL}" == "true" ]] || { echo "INFO: USE_DHI_HARBOR_PORTAL=false; keeping official Harbor portal image."; exit 0; }

if [[ -z "${DHI_HARBOR_PORTAL_IMAGE}" ]]; then
  echo "ERROR: USE_DHI_HARBOR_PORTAL=true but DHI_HARBOR_PORTAL_IMAGE is empty." >&2
  exit 1
fi

if ! docker image inspect "${DHI_HARBOR_PORTAL_IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: DHI image is not loaded locally: ${DHI_HARBOR_PORTAL_IMAGE}" >&2
  exit 1
fi

compose_file="${HARBOR_INSTALL_DIR}/docker-compose.yml"
[[ -f "$compose_file" ]] || { echo "ERROR: missing ${compose_file}" >&2; exit 1; }

backup="${compose_file}.before-dhi-portal-$(date +%Y%m%d-%H%M%S)"
tmp_compose="${compose_file}.tmp-$$"

python3 - "$compose_file" "$tmp_compose" "${DHI_HARBOR_PORTAL_IMAGE}" <<'PY'
import sys, pathlib
compose = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
image = sys.argv[3]
lines = compose.read_text().splitlines()
out = []
in_portal = False
patched = False
for line in lines:
    stripped = line.strip()
    if line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":"):
        in_portal = stripped == "portal:"
    if in_portal and stripped.startswith("image:"):
        indent = line[:len(line) - len(line.lstrip())]
        out.append(f"{indent}image: {image}")
        patched = True
        continue
    out.append(line)
if not patched:
    raise SystemExit("Could not find portal image line in docker-compose.yml")
out_path.write_text("\n".join(out) + "\n")
PY

cp -a "$compose_file" "$backup"
mv "$tmp_compose" "$compose_file"

cd "${HARBOR_INSTALL_DIR}"
if ! docker compose config --quiet; then
  cp -a "$backup" "$compose_file"
  echo "ERROR: patched docker-compose.yml is invalid; restored backup ${backup}" >&2
  exit 1
fi

if ! docker compose up -d; then
  cp -a "$backup" "$compose_file"
  echo "WARN: failed to apply DHI portal override; restoring previous compose and restarting Harbor." >&2
  docker compose up -d || true
  echo "ERROR: DHI portal override failed. Restored compose from ${backup}." >&2
  exit 1
fi

echo "INFO: Harbor portal service now uses ${DHI_HARBOR_PORTAL_IMAGE}. Previous compose saved as ${backup}."
