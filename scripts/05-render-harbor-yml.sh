#!/usr/bin/env bash
set -euo pipefail

echo "==> Rendering harbor.yml and staging TLS material"

TEMPLATE="${BUNDLE_DIR}/config/harbor.yml.template"
TARGET="${HARBOR_INSTALL_DIR}/harbor.yml"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: missing template ${TEMPLATE}" >&2; exit 1; }

install -d -m 0755 "${HARBOR_CERT_DIR}"
install -m 0600 "${BUNDLE_DIR}/${HARBOR_LEAF_KEY_SOURCE}" "${HARBOR_KEY_DEST}"

leaf_tmp="${HARBOR_CERT_DIR}/$(basename "${HARBOR_LEAF_CERT_SOURCE}")"
install -m 0644 "${BUNDLE_DIR}/${HARBOR_LEAF_CERT_SOURCE}" "$leaf_tmp"

if [[ -n "${HARBOR_CA_CERT_SOURCE}" && -f "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" ]]; then
  install -m 0644 "${BUNDLE_DIR}/${HARBOR_CA_CERT_SOURCE}" "${HARBOR_CA_CERT_DEST}"
  cat "$leaf_tmp" "${HARBOR_CA_CERT_DEST}" > "${HARBOR_CERT_DEST}"
  chmod 0644 "${HARBOR_CERT_DEST}"
else
  install -m 0644 "$leaf_tmp" "${HARBOR_CERT_DEST}"
fi

# Basic cert sanity check. This catches obvious hostname/SAN mismatch before install.
if ! openssl x509 -in "$leaf_tmp" -noout -text | grep -q "${HARBOR_HOSTNAME}"; then
  echo "WARN: ${leaf_tmp} text does not appear to contain ${HARBOR_HOSTNAME}. Docker clients may reject the cert." >&2
fi

python3 - "$TEMPLATE" "$TARGET" <<'PY'
import os, pathlib, sys
src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
text = src.read_text()
replacements = {
    "__HARBOR_HOSTNAME__": os.environ["HARBOR_HOSTNAME"],
    "__HARBOR_HTTP_PORT__": os.environ["HARBOR_HTTP_PORT"],
    "__HARBOR_HTTPS_PORT__": os.environ["HARBOR_HTTPS_PORT"],
    "__HARBOR_CERT_DEST__": os.environ["HARBOR_CERT_DEST"],
    "__HARBOR_KEY_DEST__": os.environ["HARBOR_KEY_DEST"],
    "__HARBOR_ADMIN_PASSWORD__": os.environ["HARBOR_ADMIN_PASSWORD"],
    "__HARBOR_DB_PASSWORD__": os.environ["HARBOR_DB_PASSWORD"],
    "__HARBOR_DATA_VOLUME__": os.environ["HARBOR_DATA_VOLUME"],
    "__HARBOR_LOG_DIR__": os.environ["HARBOR_LOG_DIR"],
    "__HARBOR_CONFIG_VERSION__": os.environ["HARBOR_CONFIG_VERSION"],
}
for key, value in replacements.items():
    text = text.replace(key, value)
dst.write_text(text)
PY

chmod 0600 "$TARGET"
echo "INFO: rendered ${TARGET}."
