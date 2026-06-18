# kubeharbor documentation

This folder contains the operator-facing documentation for the `kubeharbor` air-gap Harbor deployment bundle.

## Documentation index

| Document | Purpose |
| --- | --- |
| [System Design Document](System-Design-Document.md) | Complete system architecture, deployment flow, storage model, security architecture, operations model, failure modes, roadmap, and Mermaid diagrams. |
| [Operator Runbook](operator-runbook.md) | Day-0/Day-1/Day-2 operations, service management, validation, backup, reset, and break/fix procedures. |
| [Image Transfer Workflow](image-transfer-workflow.md) | Internet-connected image pull, VM clone/move, and air-gapped push workflow. |
| [Hardening Checklist](hardening-checklist.md) | Security and operational hardening checklist for the VM, Docker, Harbor, and backups. |
| [Documentation Maintenance](documentation-maintenance.md) | Documentation ownership model, diagram sync process, local render workflow, and drift-prevention rules. |
| [Diagram Workflow](../diagrams/README.md) | Local Mermaid rendering workflow for `.mmd`, SVG, PNG, and index synchronization. |

---

## Deployment summary

This bundle deploys Harbor on a single Ubuntu 24.04 LTS VM named `kubeharbor` using Docker Engine and the Docker Compose plugin.

| Resource | Value |
|---|---:|
| OS | Ubuntu 24.04 LTS |
| Hostname | kubeharbor |
| FQDN | kubeharbor.dev.kube |
| vCPU | 4 |
| RAM | 16 GB |
| OS disk | 64 GB |
| Data disk | 500 GB mounted at `/data` |
| Runtime | Docker Engine + Docker Compose plugin |
| Harbor | v2.15.1 offline installer |
| DHI portal image | `cantrellcloud/dhi-harbor-portal:2.15.1-debian` |

This is viable for a small/internal air-gapped registry. It is not a high-availability design. Treat Harbor as a platform dependency: if it is down, Kubernetes lifecycle work gets painful quickly.

## Current default DHI posture

Use the runtime Docker Hardened Image tag for steady-state deployment:

```bash
cantrellcloud/dhi-harbor-portal:2.15.1-debian
```

The `-dev` tag is for build or troubleshooting workflows only. Do not use it as the default steady-state portal image unless you are intentionally debugging hardened image behavior.

## First-read workflow

For a new operator, read these in order:

1. [System Design Document](System-Design-Document.md) to understand the architecture and design constraints.
2. [Operator Runbook](operator-runbook.md) before touching an installed VM.
3. [Image Transfer Workflow](image-transfer-workflow.md) before pulling or pushing large platform image sets.
4. [Hardening Checklist](hardening-checklist.md) before promoting the registry for production-like use.
5. [Documentation Maintenance](documentation-maintenance.md) before editing diagrams or architecture docs.

## Key operator commands

```bash
# Build the air-gap package on an Internet-connected Ubuntu staging host.
sudo ./tools/download-airgap-artifacts-on-internet-host.sh

# Install on the air-gapped kubeharbor VM.
sudo ./install.sh

# Verify Harbor state.
sudo systemctl status harbor
cd /opt/harbor && sudo docker compose ps
curl -k https://kubeharbor.dev.kube/api/v2.0/ping

# Render and synchronize documentation diagrams locally.
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
./diagrams/apply-diagram-updates.sh .
```

## Documentation asset contract

The system design document embeds Mermaid diagrams and links to rendered SVG/PNG exports. The source of truth for diagrams is `diagrams/mermaid-source/*.mmd`; generated exports live in `diagrams/svg/` and `diagrams/png/`.

Keep the following files together in the same commit whenever diagrams change:

- `docs/System-Design-Document.md`
- `diagrams/mermaid-source/*.mmd`
- `diagrams/svg/*.svg`
- `diagrams/png/*.png`
- `diagrams/DIAGRAM-INDEX.md`
- `diagrams/DIAGRAM-INDEX.json`
- `diagrams/DIAGRAM-SYNC-REPORT.md`

Splitting those files across commits creates diagram drift. That is how documentation becomes a liability instead of an asset.
