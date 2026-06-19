# kubeharbor

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Air-Gap Ready](https://img.shields.io/badge/Air--Gap-Ready-0A9396?style=for-the-badge&labelColor=001219)](#workflow-overview)
[![Offline First](https://img.shields.io/badge/Offline-First-EE9B00?style=for-the-badge&labelColor=9B2226)](#workflow-overview)
[![Shell](https://img.shields.io/badge/Shell-Bash-2A9D8F?style=for-the-badge&logo=gnu-bash&logoColor=white&labelColor=1D3557)](#command-reference)
[![Harbor](https://img.shields.io/badge/Registry-Harbor-3A86FF?style=for-the-badge&labelColor=023047)](#key-capabilities)
[![SBOM](https://img.shields.io/badge/SBOM-SPDX%20%7C%20CycloneDX-6A4C93?style=for-the-badge&labelColor=240046)](#sbom-and-transfer-artifacts)

```text
 _          _          _   _            _               
| | ___   _| |__   ___| | | | __ _ _ __| |__   ___  _ __
| |/ / | | | '_ \ / _ \ |_| |/ _` | '__| '_ \ / _ \| '__|
|   <| |_| | |_) |  __/  _  | (_| | |  | |_) | (_) | |   
|_|\_\\__,_|_.__/ \___|_| |_|\__,_|_|  |_.__/ \___/|_|   

single-node Harbor deployment and air-gap registry packaging
```

`kubeharbor` is a production-focused deployment bundle for installing Harbor on a single Ubuntu VM using Docker Engine and the Docker Compose plugin. It is built for disconnected Kubernetes platform environments that need an internal registry for RKE2, Rancher, Argo CD, Istio, Kiali, monitoring, ingress, and related platform bundles.

This repository owns the Harbor VM, registry runtime, TLS trust bootstrap, Docker data-root alignment, air-gap package creation, SBOM/provenance metadata, and optional Docker Hardened Image (DHI) portal override. It pairs with `cantrellr/k8s-airgap-images`, which owns the image catalog and pull/push workflow.

At a glance, this project provides:

- **Deterministic Harbor Packaging**: Download Docker packages, Harbor offline installer content, the configured DHI portal image, checksums, SBOMs, and provenance metadata into one moveable bundle.
- **Offline Registry Bootstrap**: Move the package to `kubeharbor`, verify checksums, extract, add certificates, edit one environment file, and run the installer without Internet access.
- **Data-Disk First Storage**: Keep Docker, containerd, Harbor data, and large image-transfer workflows on `/data` instead of the OS disk.
- **DHI Portal Compatibility Gate**: Deploy the official Harbor stack first, then safely replace only the Harbor portal service with the configured hardened image and roll back on failed health checks.
- **Transfer-Ready SBOM Output**: Generate built-in SPDX/CycloneDX artifacts and optional Syft exports with a separate SBOM archive for approval records.

Design principles for this repo:

- **Offline-first execution model** once the package is built.
- **Single-purpose registry VM** with clear operational ownership.
- **Fail-fast validation** for missing certs, bad paths, checksum failures, and portal health problems.
- **Clean repo boundaries** between Harbor lifecycle automation and Kubernetes image catalog automation.
- **Operator-readable docs** that explain what to run, why it exists, and how to recover.

This is viable for a small/internal air-gapped registry. It is **not** a high-availability Harbor design. Treat Harbor as a platform dependency: if it is down, Kubernetes lifecycle work gets painful quickly.

---

## Table of Contents

- [kubeharbor](#kubeharbor)
  - [Key Capabilities](#key-capabilities)
  - [Supported Platforms & Requirements](#supported-platforms--requirements)
  - [Target VM Profile](#target-vm-profile)
  - [Documentation Map](#documentation-map)
  - [Workflow Overview](#workflow-overview)
  - [Command Reference](#command-reference)
    - [Online staging host](#online-staging-host)
    - [Air-gapped Harbor VM](#air-gapped-harbor-vm)
    - [Image catalog handoff](#image-catalog-handoff)
  - [Configuration Reference](#configuration-reference)
  - [DHI Portal Behavior](#dhi-portal-behavior)
  - [SBOM and Transfer Artifacts](#sbom-and-transfer-artifacts)
  - [kubeharbor and k8s-airgap-images](#kubeharbor-and-k8s-airgap-images)
  - [Docker Client Trust](#docker-client-trust)
  - [Safety Controls & Idempotency](#safety-controls--idempotency)
  - [Generated Files & Directory Layout](#generated-files--directory-layout)
  - [Verification & Troubleshooting](#verification--troubleshooting)
  - [Diagram and Documentation Maintenance](#diagram-and-documentation-maintenance)

---

## Key Capabilities

- **Air-Gap Bundle Builder** – Creates a moveable tarball containing Docker packages, Harbor offline installer content, image archives, checksums, generated metadata, and operational scripts.
- **Docker Storage Alignment** – Configures Docker and containerd storage under `/data` so the 64 GB OS disk is not consumed by registry images or staging cache.
- **Harbor Offline Install** – Installs Harbor v2.15.1 from the offline installer on an Ubuntu 24.04 VM with local TLS material.
- **DHI Portal Override** – Uses `cantrellcloud/dhi-harbor-portal:2.15.1-debian13` by default, while keeping a clean escape hatch back to the official Harbor portal image.
- **SBOM + Provenance** – Emits file-level bundle manifests, SHA256 checksums, SPDX/CycloneDX SBOMs, and optional Syft-generated SPDX/CycloneDX output.
- **Image Catalog Integration** – Installs and wraps `k8s-airgap-images` so large platform image sets can be pulled while connected and pushed after the VM is moved offline.
- **Operator Runbooks** – Provides docs for deployment, hardening, image transfer, troubleshooting, diagram maintenance, and system design.

---

## Supported Platforms & Requirements

| Category | Details |
| --- | --- |
| Operating system | Ubuntu 24.04 LTS amd64 |
| Privileges | Install and package workflows require `sudo` or `root` where package managers, Docker, disk setup, or Harbor lifecycle operations are used |
| Runtime | Docker Engine + Docker Compose plugin |
| Harbor version | v2.15.1 offline installer |
| Target hostname | `kubeharbor.dev.kube` by default |
| Connectivity | Internet required only on the staging host while downloading artifacts. The target VM is intended to install offline |
| Certificates | Harbor server certificate, matching private key, and CA certificate copied into `certs/` before install |
| Optional tooling | `syft` for additional SPDX/CycloneDX SBOM exports. Built-in SBOM/provenance output is generated without Syft |
| Companion repo | `cantrellr/k8s-airgap-images` for source image lists, pull/push workflows, and Harbor project preflight |

---

## Target VM Profile

| Resource | Value |
| --- | ---: |
| OS | Ubuntu 24.04 LTS |
| Hostname | `kubeharbor` |
| FQDN | `kubeharbor.dev.kube` |
| vCPU | 4 |
| RAM | 16 GB |
| OS disk | 64 GB |
| Data disk | 500 GB mounted at `/data` |
| Runtime | Docker Engine + Docker Compose plugin |
| Harbor | v2.15.1 offline installer |
| DHI portal image | `cantrellcloud/dhi-harbor-portal:2.15.1-debian13` |

---

## Documentation Map

| Document | Purpose |
| --- | --- |
| [docs/System-Design-Document.md](docs/System-Design-Document.md) | System architecture, deployment model, runtime model, storage, security, operations, failure modes, and Mermaid diagrams. |
| [docs/operator-runbook.md](docs/operator-runbook.md) | Start/stop/status, reconfiguration, reset, validation, backup, and break/fix procedures. |
| [docs/image-transfer-workflow.md](docs/image-transfer-workflow.md) | Internet-connected pull, VM clone/move, and air-gapped push workflow using `k8s-airgap-images`. |
| [docs/k8s-airgap-images-integration.md](docs/k8s-airgap-images-integration.md) | Ownership boundaries between kubeharbor and the image catalog. |
| [docs/sbom-airgap.md](docs/sbom-airgap.md) | SBOM and provenance generation for the moveable air-gap package. |
| [docs/hardening-checklist.md](docs/hardening-checklist.md) | VM, network, Docker, Harbor, backup, and recovery hardening checklist. |
| [docs/documentation-maintenance.md](docs/documentation-maintenance.md) | How to maintain docs, diagrams, rendered assets, and index metadata. |
| [diagrams/README.md](diagrams/README.md) | Local Mermaid rendering workflow. Use this when updating diagrams. |

---

## Workflow Overview

1. **Online staging:** Run `tools/download-airgap-artifacts-on-internet-host.sh` on an Internet-connected Ubuntu host. The script downloads Docker packages, the Harbor offline installer, the configured DHI portal image, checksums, SBOM metadata, and produces transfer artifacts under `output/`.
2. **Transfer:** Move the main package, main package checksum, SBOM archive, and SBOM checksum to the air-gapped `kubeharbor` VM.
3. **Air-gapped extraction:** Verify SHA256 checksums, extract the tarball, copy TLS material into `certs/`, and review `config/harbor.env`.
4. **Install:** Run `sudo ./install.sh`. The installer prepares storage, installs Docker packages from the bundle, loads images, installs Harbor, applies TLS settings, starts services, and optionally replaces the portal container with the configured DHI image.
5. **Operate:** Use the runbook for start/stop/status, backup, restore, upgrade prep, and break/fix procedures.
6. **Image catalog handoff:** Use `k8s-airgap-images` to pull large Kubernetes platform image lists while connected, then push cached images into Harbor after the VM is moved or cloned into the air-gapped environment.

Harbor startup defaults to serial orchestration to avoid logger startup races: start `harbor-log`, wait for the local syslog listener, then start the remaining Harbor services.

---

## Command Reference

### Online staging host

Run the normal bundle build:

```bash
sudo ./tools/download-airgap-artifacts-on-internet-host.sh
```

Require Syft-generated SBOMs in addition to built-in SBOM/provenance output:

```bash
sudo INSTALL_SYFT_FOR_SBOM=true REQUIRE_SYFT_FOR_SBOM=true \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

Reuse already-downloaded content and regenerate package metadata/tarballs:

```bash
sudo DOWNLOAD_DOCKER_DEBS=false \
     DOWNLOAD_HARBOR=false \
     DOWNLOAD_DHI_IMAGE=false \
     ./tools/download-airgap-artifacts-on-internet-host.sh
```

Override the DHI image for controlled testing:

```bash
sudo DHI_HARBOR_PORTAL_IMAGE="cantrellcloud/dhi-harbor-portal:<alternate-tag>" \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

`DHI_IMAGE` remains accepted as a legacy alias, but `DHI_HARBOR_PORTAL_IMAGE` is the source-of-truth variable used by both the downloader and the air-gapped installer.

### Air-gapped Harbor VM

Verify, extract, add certs, and install:

```bash
sha256sum -c kubeharbor-airgap-v2.15.1-<timestamp>.tgz.sha256
sha256sum -c kubeharbor-airgap-v2.15.1-<timestamp>-sbom.tgz.sha256

tar -xzf kubeharbor-airgap-v2.15.1-<timestamp>.tgz
cd kubeharbor

cp /secure/path/kubeharbor.dev.kube.crt certs/
cp /secure/path/kubeharbor.dev.kube.key certs/
cp /secure/path/ca.crt certs/

vi config/harbor.env
sudo ./install.sh
```

Validate the Docker data root before large image acquisition:

```bash
sudo docker info --format '{{.DockerRootDir}}'
```

Expected:

```text
/data/docker
```

### Image catalog handoff

Stage `k8s-airgap-images` onto `/data`:

```bash
sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace
```

Stage from an archive or Git URL:

```bash
sudo ./tools/install-k8s-airgap-images.sh /transfer/k8s-airgap-images.tgz --replace

sudo ./tools/install-k8s-airgap-images.sh \
  --source https://github.com/cantrellr/k8s-airgap-images.git \
  --replace
```

Pull all images while the VM still has Internet access:

```bash
sudo ./tools/pull-images-to-data-cache.sh
```

After the VM is cloned, moved, or re-IP'd into the air-gapped environment, push cached images into Harbor:

```bash
sudo ./tools/push-data-cache-to-harbor.sh --target kubeharbor.dev.kube/library
```

The default push mode is `strip-registry`, so upstream references are mapped under the Harbor `library` project without the source registry hostname.

---

## Configuration Reference

Current storage defaults in `config/harbor.env`:

```bash
HARBOR_DATA_VOLUME="/data"
DOCKER_DATA_ROOT="/data/docker"
CONTAINERD_ROOT="/data/containerd"
IMAGE_TRANSFER_ROOT="/data/k8s-airgap-images"
```

For an existing `/data` mount, leave:

```bash
PREPARE_DATA_DISK="true"
FORMAT_DATA_DISK="false"
DATA_DISK_DEVICE=""
```

For a blank disk you want the installer to format, validate the device with `lsblk` first, then use a value like:

```bash
DATA_DISK_DEVICE="/dev/sdb"
FORMAT_DATA_DISK="true"
```

Recommended DHI portal setting:

```bash
USE_DHI_HARBOR_PORTAL="true"
DHI_HARBOR_PORTAL_IMAGE="cantrellcloud/dhi-harbor-portal:2.15.1-debian13"
```

---

## DHI Portal Behavior

The official Harbor offline installer deploys the complete Harbor stack first. Then this bundle swaps only the `portal` service to the configured DHI image.

The override script patches Harbor's generated portal `nginx.conf` for the DHI image's 8080/non-root runtime model, validates the config inside the DHI image, recreates only the portal service, and rolls back if the portal does not remain healthy.

To deploy the official Harbor image set without the DHI portal override:

```bash
USE_DHI_HARBOR_PORTAL="false"
```

Use that as a break/fix escape hatch, not as the desired steady state unless the DHI compatibility gate fails.

---

## SBOM and Transfer Artifacts

Every normal package build produces four files to move together:

```text
output/kubeharbor-airgap-v2.15.1-<timestamp>.tgz
output/kubeharbor-airgap-v2.15.1-<timestamp>.tgz.sha256
output/kubeharbor-airgap-v2.15.1-<timestamp>-sbom.tgz
output/kubeharbor-airgap-v2.15.1-<timestamp>-sbom.tgz.sha256
```

The main package includes the `sbom/` directory internally. The external SBOM archive exists for transfer approval records and offline review before extraction.

Generated SBOM files include:

- `sbom/airgap-bundle-manifest.json`
- `sbom/airgap-bundle-summary.txt`
- `sbom/airgap-bundle.cyclonedx.json`
- `sbom/airgap-bundle.spdx.json`
- `sbom/syft-cyclonedx.json` when Syft is available
- `sbom/syft-spdx.json` when Syft is available
- `sbom/SHA256SUMS`

Full details are in [docs/sbom-airgap.md](docs/sbom-airgap.md).

---

## kubeharbor and k8s-airgap-images

Keep the ownership boundary clean:

| Capability | kubeharbor | k8s-airgap-images |
| --- | --- | --- |
| Harbor install and runtime lifecycle | Owns | Does not own |
| Docker/containerd storage under `/data` | Owns | Consumes |
| TLS and client trust | Owns | Requires working trust |
| Source image catalog | References | Owns |
| Pull/push workflows | Wraps | Owns |
| Harbor project preflight | Delegates | Owns via Harbor API |

Read [docs/k8s-airgap-images-integration.md](docs/k8s-airgap-images-integration.md) before changing the image-transfer model.

---

## Docker Client Trust

On every Docker client that will push to or pull from Harbor:

```bash
sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt
sudo docker login kubeharbor.dev.kube
```

For RKE2/containerd nodes, configure trust in the RKE2/containerd registry configuration instead of Docker's `/etc/docker/certs.d` path.

---

## Safety Controls & Idempotency

- Package generation can be rerun. Existing downloads can be reused with `DOWNLOAD_*` controls.
- Checksum verification is required before extraction in the air-gapped environment.
- The installer validates certificate material before applying Harbor TLS configuration.
- Docker and containerd storage are intentionally moved to `/data` before large image activity.
- The DHI portal override changes only the portal service and includes a rollback path.
- The image catalog tooling remains separate so Harbor lifecycle changes do not mutate source image lists.

---

## Generated Files & Directory Layout

```text
kubeharbor/
├── config/                         # harbor.env and example runtime settings
├── certs/                          # Local TLS material copied by the operator
├── docs/                           # System design, runbook, SBOM, hardening, integration docs
├── diagrams/                       # Mermaid source and rendered diagram workflow
├── installers/                     # Downloaded Harbor offline installer content
├── images/                         # Saved DHI image archive and image references
├── packages/docker-debs/           # Downloaded Docker/containerd .deb packages
├── sbom/                           # Generated SBOM, provenance, and checksum metadata
├── output/                         # Moveable air-gap package and SBOM archive
├── scripts/                        # Install and helper scripts used by install.sh
├── tools/                          # Online downloader, cleanup, and image catalog handoff scripts
└── install.sh                      # Air-gapped Harbor installer entrypoint
```

---

## Verification & Troubleshooting

Useful checks after extraction or install:

```bash
sha256sum -c kubeharbor-airgap-v2.15.1-<timestamp>.tgz.sha256
( cd sbom && sha256sum -c SHA256SUMS )
sudo docker info --format '{{.DockerRootDir}}'
sudo docker compose ps
sudo docker logs harbor-portal --tail 100
```

When troubleshooting, start with:

- [docs/operator-runbook.md](docs/operator-runbook.md) for operational commands and reset guidance.
- [docs/hardening-checklist.md](docs/hardening-checklist.md) for security and recovery checks.
- [docs/image-transfer-workflow.md](docs/image-transfer-workflow.md) for image pull/push issues.
- [docs/sbom-airgap.md](docs/sbom-airgap.md) for SBOM and transfer metadata behavior.

---

## Diagram and Documentation Maintenance

GitHub Actions are not required for this repo. Diagrams are rendered locally with Mermaid CLI.

First-time workstation setup and sync:

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

Normal re-sync after editing diagram source or the system design document:

```bash
./diagrams/apply-diagram-updates.sh .
```

Do not run the diagram renderer with `sudo`. It should run as your normal user. The browser dependency installer uses `sudo` internally only for `apt-get`.
