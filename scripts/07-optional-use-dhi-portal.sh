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
cp -a "$compose_file" "$backup"

python3 - "$compose_file" "${DHI_HARBOR_PORTAL_IMAGE}" <<'PY'
import sys, pathlib
compose = pathlib.Path(sys.argv[1])
image = sys.argv[2]
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
compose.write_text("\n".join(out) + "\n")
PY

cd "${HARBOR_INSTALL_DIR}"
docker compose down
docker compose up -d

echo "INFO: Harbor portal service now uses ${DHI_HARBOR_PORTAL_IMAGE}. Previous compose saved as ${backup}."
