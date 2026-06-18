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
- No outbound Internet from the VM after it enters the air-gapped environment.
- Allow only approved internal DNS/NTP/logging/backup destinations.

## Docker

- Use Docker Engine packages staged from a trusted build/download host.
- Keep Docker rootful for Harbor supportability.
- Do not disable Docker iptables management unless you are explicitly replacing all Docker networking rules.
- Use log rotation in `/etc/docker/daemon.json`.
- Restrict membership in the `docker` group; Docker group is effectively root.
- Confirm Docker root lives under `/data/docker` before large image pulls.

## Harbor

- Use internal CA-signed TLS certificate with SAN for the Harbor FQDN.
- Distribute only the CA certificate (`ca.crt`) to Harbor clients and nodes.
- Change the default admin password before install.
- Use the DHI Harbor portal runtime tag by default: `cantrellcloud/dhi-harbor-portal:2.15.1-debian`.
- Do not use the `-dev` DHI tag for steady-state production-style deployment unless you are intentionally troubleshooting.
- Disable self-registration unless there is a governance reason to allow it.
- Create named users or integrate identity; avoid shared admin workflows.
- Use projects, quotas, retention policies, and immutable tags for platform images.
- Enable vulnerability scanning only after offline Trivy DB management is defined.
- Define replication rules only after trust and namespace strategy are agreed.

## SBOM and artifact provenance

- Generate SBOM/provenance metadata on the Internet-connected staging host before creating the moveable tarball.
- Keep `GENERATE_SBOM=true` for normal package builds.
- Keep `REQUIRE_AIRGAP_SBOM=true` for air-gapped installs unless you are intentionally consuming a legacy package.
- Move these four artifacts together: package tarball, package checksum, SBOM archive, and SBOM archive checksum.
- Validate SBOM checksums before install:

```bash
( cd sbom && sha256sum -c SHA256SUMS )
```

- Use `INSTALL_SYFT_FOR_SBOM=true REQUIRE_SYFT_FOR_SBOM=true` when policy requires Syft-generated SPDX/CycloneDX output in addition to the built-in file-level SBOM.
- Do not include private keys, Docker credentials, `.git`, or `output/` in SBOM scope.
- Store SBOM archives with the transfer approval record or change ticket.

## Backups and recovery

- Back up `/data` and `/opt/harbor` before upgrades.
- Test restore before calling it production-ready.
- Keep the exact offline installer version used for each deployment/upgrade.
- Keep checksums for Docker packages, Harbor installer artifacts, saved image tarballs, and generated SBOM archives.
- Document who owns certificate renewal, backup execution, backup validation, and restore authority.

## Documentation and diagram asset integrity

- Keep Mermaid source, rendered SVG/PNG files, Markdown links, and diagram indexes in the same commit.
- Do not hand-edit generated SVG or PNG exports.
- Do not commit `.diagram-tools/`, `node_modules/`, or `.diagram-sync-updated-files.txt`.
- Run the local diagram sync wrapper after diagram changes:

```bash
./diagrams/apply-diagram-updates.sh .
```

- Validate the system design document still has the expected diagram count:

```bash
grep -c '```mermaid' docs/System-Design-Document.md
grep -c 'Diagram export:' docs/System-Design-Document.md
```

Expected current count: `12` for both commands.
