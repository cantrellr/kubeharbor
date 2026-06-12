# kubeharbor hardening checklist

## VM and OS

- Use Ubuntu 24.04 LTS hardened baseline.
- Static IP, stable DNS, and correct forward/reverse lookup for `kubeharbor.dev.kube`.
- Mount the 500 GB data disk at `/data` before production use.
- NTP/chrony synchronized with the same time source as Kubernetes nodes.
- SSH key-only access; no password SSH.
- Limit sudo to named admin accounts.
- Apply your standard auditd/syslog forwarding baseline.

## Network

- Required inbound: TCP 443 from admins, Kubernetes nodes, image staging hosts, and CI/CD systems.
- Optional inbound: TCP 80 only if you want redirect workflows. In a closed lab, 443-only is cleaner.
- No outbound Internet from the VM.
- Allow only approved internal DNS/NTP/logging/backup destinations.

## Docker

- Use Docker Engine packages staged from a trusted build/download host.
- Keep Docker rootful for Harbor supportability.
- Do not disable Docker iptables management unless you are explicitly replacing all Docker networking rules.
- Use log rotation in `/etc/docker/daemon.json`.
- Restrict membership in the `docker` group; Docker group is effectively root.

## Harbor

- Use internal CA-signed TLS certificate with SAN for the Harbor FQDN.
- Do not leave the CA private key on the Harbor VM.
- Change the default admin password before install.
- Disable self-registration unless there is a governance reason to allow it.
- Create named users or integrate identity; avoid shared admin workflows.
- Use projects, quotas, retention policies, and immutable tags for platform images.
- Enable vulnerability scanning only after offline Trivy DB management is defined.
- Define replication rules only after trust and namespace strategy are agreed.

## Backups and recovery

- Back up `/data` and `/opt/harbor` before upgrades.
- Test restore before calling it production-ready.
- Keep the exact offline installer version used for each deployment/upgrade.
- Keep checksums for Docker packages, Harbor installer artifacts, and saved image tarballs.
