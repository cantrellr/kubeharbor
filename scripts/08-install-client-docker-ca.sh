#!/usr/bin/env bash
set -euo pipefail

# Run on every Docker client that will push/pull from Harbor.
# Usage: sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt [443]

host="${1:-}"
ca_file="${2:-}"
port="${3:-443}"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi
if [[ -z "$host" || -z "$ca_file" || ! -f "$ca_file" ]]; then
  echo "Usage: sudo $0 <harbor-fqdn> <ca.crt> [port]" >&2
  exit 1
fi

if [[ "$port" == "443" ]]; then
  cert_dir="/etc/docker/certs.d/${host}"
else
  cert_dir="/etc/docker/certs.d/${host}:${port}"
fi

install -d -m 0755 "$cert_dir"
install -m 0644 "$ca_file" "${cert_dir}/ca.crt"
systemctl restart docker

echo "Installed Docker registry CA trust at ${cert_dir}/ca.crt"
