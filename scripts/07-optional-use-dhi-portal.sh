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
portal_nginx_conf="${HARBOR_INSTALL_DIR}/common/config/portal/nginx.conf"

[[ -f "${compose_file}" ]] || { echo "ERROR: missing ${compose_file}" >&2; exit 1; }
[[ -f "${portal_nginx_conf}" ]] || { echo "ERROR: missing Harbor portal nginx config: ${portal_nginx_conf}" >&2; exit 1; }

backup="${compose_file}.before-dhi-portal-$(date +%Y%m%d-%H%M%S)"
nginx_backup="${portal_nginx_conf}.before-dhi-portal-$(date +%Y%m%d-%H%M%S)"
tmp_compose="${compose_file}.tmp-$$"
tmp_nginx="${portal_nginx_conf}.tmp-$$"

cp -a "${compose_file}" "${backup}"
cp -a "${portal_nginx_conf}" "${nginx_backup}"

# Docker Hardened harbor-portal expects a custom nginx config at /etc/nginx/nginx.conf,
# serves on 8080, and runtime variants may run as non-root. Make the generated Harbor
# portal nginx config safe for that model before changing the Compose image.
python3 - "${portal_nginx_conf}" "${tmp_nginx}" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
text = src.read_text()

# Preserve Harbor's generated routing, but normalize the nginx runtime paths for DHI/non-root use.
if not re.search(r'^\s*pid\s+', text, flags=re.M):
    text = re.sub(r'(?m)^(\s*worker_processes\b[^;]*;\s*)$', r'\1\npid /tmp/nginx.pid;', text, count=1)
else:
    text = re.sub(r'(?m)^\s*pid\s+[^;]+;', 'pid /tmp/nginx.pid;', text, count=1)

# DHI docs show harbor-portal listening on 8080. Harbor's nginx front-end expects portal:8080.
text = re.sub(r'(?m)^(\s*listen\s+)80(\s*;)', r'\g<1>8080\2', text)

required_http_directives = [
    'client_body_temp_path /tmp/client_body_temp;',
    'proxy_temp_path /tmp/proxy_temp;',
    'fastcgi_temp_path /tmp/fastcgi_temp;',
    'uwsgi_temp_path /tmp/uwsgi_temp;',
    'scgi_temp_path /tmp/scgi_temp;',
]
missing = [d for d in required_http_directives if d.split()[0] not in text]

if missing:
    lines = text.splitlines()
    inserted = False
    new_lines = []
    for line in lines:
        new_lines.append(line)
        if not inserted and re.match(r'^\s*http\s*{\s*$', line):
            indent = re.match(r'^(\s*)', line).group(1) + '    '
            new_lines.extend(indent + d for d in missing)
            inserted = True
    if not inserted:
        raise SystemExit('Could not find http { block in Harbor portal nginx config')
    text = '\n'.join(new_lines) + '\n'

out.write_text(text)
PY

mv "${tmp_nginx}" "${portal_nginx_conf}"
chmod 0644 "${portal_nginx_conf}"

# Patch only the portal service image and remove any forced user override. DHI runtime
# variants are designed to run non-root. Forcing root is not a compatibility strategy.
python3 - "${compose_file}" "${tmp_compose}" "${DHI_HARBOR_PORTAL_IMAGE}" <<'PY'
import pathlib
import sys

compose = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
image = sys.argv[3]
lines = compose.read_text().splitlines()
out = []
in_portal = False
patched = False
portal_mount_seen = False
portal_volumes_seen = False
portal_volumes_indent = None
portal_service_indent = '  '
portal_child_indent = '    '
mount_line = '      - ./common/config/portal/nginx.conf:/etc/nginx/nginx.conf:ro'

def is_service_header(line: str) -> bool:
    stripped = line.strip()
    return line.startswith('  ') and not line.startswith('    ') and stripped.endswith(':')

def close_portal_if_needed():
    global portal_mount_seen, portal_volumes_seen
    if not in_portal or portal_mount_seen:
        return
    if not portal_volumes_seen:
        out.append(f'{portal_child_indent}volumes:')
    out.append(mount_line)
    portal_mount_seen = True

for line in lines:
    stripped = line.strip()

    if is_service_header(line):
        if in_portal:
            close_portal_if_needed()
        in_portal = stripped == 'portal:'
        if in_portal:
            portal_mount_seen = False
            portal_volumes_seen = False
            portal_volumes_indent = None
        out.append(line)
        continue

    if in_portal and stripped.startswith('image:'):
        indent = line[: len(line) - len(line.lstrip())]
        out.append(f'{indent}image: {image}')
        patched = True
        continue

    # Remove user overrides from portal. Let the DHI image metadata decide root/non-root.
    if in_portal and stripped.startswith('user:'):
        continue

    if in_portal and stripped == 'volumes:':
        portal_volumes_seen = True
        portal_volumes_indent = line[: len(line) - len(line.lstrip())]
        out.append(line)
        continue

    if in_portal and '/etc/nginx/nginx.conf' in stripped:
        portal_mount_seen = True
        out.append(line)
        continue

    out.append(line)

if in_portal:
    close_portal_if_needed()

if not patched:
    raise SystemExit('Could not find portal image line in docker-compose.yml')

out_path.write_text('\n'.join(out) + '\n')
PY

mv "${tmp_compose}" "${compose_file}"

cd "${HARBOR_INSTALL_DIR}"

if ! docker compose config --quiet; then
  cp -a "${backup}" "${compose_file}"
  cp -a "${nginx_backup}" "${portal_nginx_conf}"
  echo "ERROR: patched docker-compose.yml is invalid; restored ${backup}" >&2
  exit 1
fi

# Validate nginx can parse the Harbor-generated portal config inside the DHI image.
# Use the Harbor Compose network when available so service names such as core/harbor-core resolve.
harbor_network=""
core_container="$(docker compose ps -q core 2>/dev/null || true)"
if [[ -n "${core_container}" ]]; then
  harbor_network="$(docker inspect "${core_container}" --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' 2>/dev/null | head -n1 || true)"
fi

network_args=()
if [[ -n "${harbor_network}" ]]; then
  network_args=(--network "${harbor_network}")
fi

echo "INFO: validating DHI portal nginx compatibility before recreating portal."
if ! docker run --rm \
  "${network_args[@]}" \
  --entrypoint nginx \
  -v "${portal_nginx_conf}:/etc/nginx/nginx.conf:ro" \
  "${DHI_HARBOR_PORTAL_IMAGE}" \
  -t -c /etc/nginx/nginx.conf; then
  cp -a "${backup}" "${compose_file}"
  cp -a "${nginx_backup}" "${portal_nginx_conf}"
  echo "ERROR: DHI portal image failed nginx config validation. Restored previous Compose/config files." >&2
  exit 1
fi

if ! docker compose up -d --force-recreate portal; then
  cp -a "${backup}" "${compose_file}"
  cp -a "${nginx_backup}" "${portal_nginx_conf}"
  echo "WARN: failed to apply DHI portal override; restoring previous compose/config and restarting Harbor." >&2
  docker compose up -d || true
  echo "ERROR: DHI portal override failed. Restored compose from ${backup}." >&2
  exit 1
fi

portal_container="$(docker compose ps -q portal 2>/dev/null || true)"
for _ in $(seq 1 12); do
  if [[ -n "${portal_container}" ]] && [[ "$(docker inspect "${portal_container}" --format '{{.State.Running}}' 2>/dev/null || echo false)" == "true" ]]; then
    sleep 2
    if [[ "$(docker inspect "${portal_container}" --format '{{.State.Running}}' 2>/dev/null || echo false)" == "true" ]]; then
      echo "INFO: Harbor portal service now uses ${DHI_HARBOR_PORTAL_IMAGE}. Previous compose saved as ${backup}."
      echo "INFO: Previous portal nginx config saved as ${nginx_backup}."
      exit 0
    fi
  fi
  sleep 2
  portal_container="$(docker compose ps -q portal 2>/dev/null || true)"
done

cp -a "${backup}" "${compose_file}"
cp -a "${nginx_backup}" "${portal_nginx_conf}"
echo "WARN: DHI portal container did not remain running; restoring official portal image and nginx config." >&2
docker compose up -d || true
echo "ERROR: DHI portal override failed health gate. Restored compose from ${backup}." >&2
exit 1
