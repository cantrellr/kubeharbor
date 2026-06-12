#!/usr/bin/env bash
set -euo pipefail

# Optional helper for lab/offline PKI workflows.
# If you already have a signed leaf cert/key, do not use this.
# Usage: ./tools/create-leaf-cert-with-local-ca.sh kubeharbor.dev.kube 10.0.4.70

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FQDN="${1:-kubeharbor.dev.kube}"
IP="${2:-}"
CA_CERT="${BUNDLE_DIR}/certs/ca.crt"
CA_KEY="${BUNDLE_DIR}/certs/ca.key"
LEAF_KEY="${BUNDLE_DIR}/certs/kubeharbor.dev.kube.key"
LEAF_CSR="${BUNDLE_DIR}/certs/kubeharbor.dev.kube.csr"
LEAF_CERT="${BUNDLE_DIR}/certs/kubeharbor.dev.kube.crt"
EXTFILE="${BUNDLE_DIR}/certs/kubeharbor.dev.kube.ext"

[[ -f "$CA_CERT" && -f "$CA_KEY" ]] || { echo "ERROR: expected ${CA_CERT} and ${CA_KEY}" >&2; exit 1; }

SAN="DNS:${FQDN},DNS:kubeharbor"
if [[ -n "$IP" ]]; then
  SAN="${SAN},IP:${IP}"
fi

cat > "$EXTFILE" <<EOF_EXT
subjectAltName=${SAN}
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
basicConstraints=CA:FALSE
EOF_EXT

openssl genrsa -out "$LEAF_KEY" 4096
openssl req -new -key "$LEAF_KEY" -out "$LEAF_CSR" -subj "/CN=${FQDN}"
openssl x509 -req -in "$LEAF_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$LEAF_CERT" -days 825 -sha256 -extfile "$EXTFILE"
chmod 0600 "$LEAF_KEY"

echo "Created ${LEAF_CERT} and ${LEAF_KEY}. Remove ca.key from this VM when done."
