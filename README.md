# kubeHarbor Docker -- Air-Gap Deployment Bundle

This bundle deploys Harbor on a single Ubuntu 24.04 LTS VM named `kubeharbor` using Docker Engine and the Docker Compose plugin. It is designed for disconnected Kubernetes platform environments that need an internal image registry for RKE2, Rancher, Argo CD, Istio, monitoring, and related platform bundles.

This is viable for a small/internal air-gapped registry. It is **not** a high-availability design. Treat Harbor as a platform dependency: if it is down, Kubernetes lifecycle work gets painful quickly.

## Documentation map

| Document | Purpose |
| --- | --- |
| [docs/System-Design-Document.md](docs/System-Design-Document.md) | System architecture, deployment model, runtime model, storage, security, operations, failure modes, and Mermaid diagrams. |
| [docs/operator-runbook.md](docs/operator-runbook.md) | Start/stop/status, reconfiguration, reset, validation, backup, and break/fix procedures. |
| [docs/image-transfer-workflow.md](docs/image-transfer-workflow.md) | Internet-connected pull, VM clone/move, and air-gapped push workflow using `k8s-airgap-images`. |
| [docs/sbom-airgap.md](docs/sbom-airgap.md) | SBOM and provenance generation for the moveable air-gap package. |
| [docs/hardening-checklist.md](docs/hardening-checklist.md) | VM, network, Docker, Harbor, backup, and recovery hardening checklist. |
| [docs/documentation-maintenance.md](docs/documentation-maintenance.md) | How to maintain docs, diagrams, rendered SVG/PNG assets, and index metadata. |
| [diagrams/README.md](diagrams/README.md) | Local Mermaid rendering workflow. Use this when updating diagrams. |

## Target VM

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

## Recommended DHI image tag

Use the runtime Docker Hardened Image tag that matches the Harbor version deployed by the offline installer:

```bash
cantrellcloud/dhi-harbor-portal:2.15.1-debian
```

Do not use the `-dev` variant as the default steady-state portal image. The `-dev` tag is intended for build/troubleshooting workflows and usually carries a larger runtime footprint. Use it only when you are intentionally debugging or validating hardened image behavior.

## Storage defaults

The VM has a 64 GB OS disk and a 500 GB data disk. Large image workflows must not land under `/var/lib/docker` on the OS disk.

Current defaults in `config/harbor.env`:

```bash
HARBOR_DATA_VOLUME="/data"
DOCKER_DATA_ROOT="/data/docker"
CONTAINERD_ROOT="/data/containerd"
IMAGE_TRANSFER_ROOT="/data/k8s-airgap-images"
```

The Docker installer writes both Docker and containerd storage settings so the local pull cache lives on `/data` before large image acquisition starts.

Validate before pulling the application image list:

```bash
sudo docker info --format '{{.DockerRootDir}}'
```

Expected:

```text
/data/docker
```

## What the Internet staging script does

Run this on an Internet-connected Ubuntu 24.04 amd64 staging host:

```bash
sudo ./tools/download-airgap-artifacts-on-internet-host.sh
```

The script:

1. Adds the official Docker apt repo on the staging host.
2. Downloads Docker Engine, CLI, containerd, Buildx, Compose plugin, and dependency `.deb` files into `packages/docker-debs/`.
3. Downloads the Harbor offline installer into `installers/`.
4. Prompts for Docker username and password/access token when required.
5. Runs `docker pull cantrellcloud/dhi-harbor-portal:2.15.1-debian` by default.
6. Saves that image into `images/*.tar`.
7. Generates SHA256 files for Docker packages, the Harbor installer, and saved image archives.
8. Generates SBOM and provenance metadata under `sbom/`.
9. Creates one moveable tarball under `output/`.
10. Creates an external SBOM archive under `output/` so transfer records can carry SBOM metadata independently from the tarball.

To require Syft-generated SBOMs in addition to the built-in file-level SPDX/CycloneDX output:

```bash
sudo INSTALL_SYFT_FOR_SBOM=true REQUIRE_SYFT_FOR_SBOM=true \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

To override the DHI tag for testing:

```bash
sudo DHI_IMAGE="cantrellcloud/dhi-harbor-portal:2.15.1-debian-dev" \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

## SBOM and transfer artifacts

Every normal package build now produces four files to move together:

```text
output/kubeharbor-airgap-v2.15.1-<timestamp>.tgz
output/kubeharbor-airgap-v2.15.1-<timestamp>.tgz.sha256
output/kubeharbor-airgap-v2.15.1-<timestamp>-sbom.tgz
output/kubeharbor-airgap-v2.15.1-<timestamp>-sbom.tgz.sha256
```

The main package includes the `sbom/` directory internally. The external SBOM archive is there for transfer approval records and offline review before extraction. Full details are in [docs/sbom-airgap.md](docs/sbom-airgap.md).

## Air-gap deployment flow

On `kubeharbor`:

```bash
sha256sum -c kubeharbor-airgap-v2.15.1-<timestamp>.tgz.sha256
tar -xzf kubeharbor-airgap-v2.15.1-<timestamp>.tgz
cd kubeharbor-docker-airgap-bundle-v2
( cd sbom && sha256sum -c SHA256SUMS )
```

Copy your certs into `certs/`:

```bash
cp /secure/path/kubeharbor.dev.kube.crt certs/
cp /secure/path/kubeharbor.dev.kube.key certs/
cp /secure/path/ca.crt certs/
```

Edit deployment settings:

```bash
vi config/harbor.env
```

For the 500 GB data disk, set one of these paths.

### Existing `/data` mount

If `/data` is already formatted and mounted, leave:

```bash
PREPARE_DATA_DISK="true"
FORMAT_DATA_DISK="false"
DATA_DISK_DEVICE=""
```

### Blank disk you want the installer to format

Example only. Validate the device with `lsblk` first.

```bash
DATA_DISK_DEVICE="/dev/sdb"
FORMAT_DATA_DISK="true"
```

Then deploy:

```bash
sudo ./install.sh
```

Harbor startup defaults to serial orchestration to avoid logger startup races:

1. Start `harbor-log` first.
2. Wait for `127.0.0.1:1514` listener readiness.
3. Start remaining Harbor services.

## DHI portal behavior

By default, the bundle downloads, loads, and attempts to use the DHI Harbor portal runtime image:

```bash
USE_DHI_HARBOR_PORTAL="true"
DHI_HARBOR_PORTAL_IMAGE="cantrellcloud/dhi-harbor-portal:2.15.1-debian"
```

The official Harbor offline installer still deploys the complete Harbor stack first. Then the bundle swaps only the `portal` service to the DHI image. The override script patches Harbor's generated portal `nginx.conf` for DHI's 8080/non-root runtime model, validates the config inside the DHI image, recreates only the portal service, and rolls back if the portal does not remain healthy.

To deploy the official Harbor image set without the DHI portal override:

```bash
USE_DHI_HARBOR_PORTAL="false"
```

That escape hatch is useful for break/fix validation. Do not treat it as the desired steady-state unless the DHI image compatibility gate fails.

## Large image pull/push workflow

Use this when you have an Internet-connected VM with the kubeharbor repo and the separate `k8s-airgap-images` repository.

Stage `k8s-airgap-images` onto `/data`:

```bash
sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace
```

You can also stage from an archive or Git URL:

```bash
sudo ./tools/install-k8s-airgap-images.sh /transfer/k8s-airgap-images.tgz --replace

sudo K8S_AIRGAP_IMAGES_SOURCE=https://github.com/<owner>/k8s-airgap-images.git \
  ./tools/install-k8s-airgap-images.sh --replace
```

Pull all images while the VM still has Internet access:

```bash
sudo ./tools/pull-images-to-data-cache.sh
```

After the VM is cloned and moved/re-IP'd into the air-gapped environment, push the locally cached images into the reachable Harbor registry:

```bash
sudo ./tools/push-data-cache-to-harbor.sh --target kubeharbor.dev.kube/library
```

The default push mode is `strip-registry`, so upstream references are mapped under the Harbor `library` project without the source registry hostname. Full details are in [docs/image-transfer-workflow.md](docs/image-transfer-workflow.md).

The legacy `image-airgap-bundle-updated.zip` flow is deprecated. `tools/install-image-airgap-bundle.sh` remains only as a compatibility shim and redirects to `tools/install-k8s-airgap-images.sh`.

## Docker client trust

On every Docker client that will push/pull from Harbor:

```bash
sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt
sudo docker login kubeharbor.dev.kube
```

For RKE2/containerd nodes, configure trust in the RKE2/containerd registry configuration instead of Docker's `/etc/docker/certs.d` path.

## Diagram and documentation maintenance

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

## Service startup behavior

`harbor.service` uses `/usr/local/sbin/harbor-start-serial.sh`, so `systemctl start harbor` follows the same serial log-bootstrap sequence as installer startup.

## Reset downloaded artifacts / clean slate

Run this on the Internet-connected staging host when you want to purge previously downloaded artifacts and rebuild the air-gap tarball from scratch.

```bash
sudo ./tools/clean-airgap-downloads.sh --dry-run
sudo ./tools/clean-airgap-downloads.sh --yes
```

Default cleanup removes generated/downloaded bundle content only: Docker `.deb` files, Harbor offline installer files, saved Docker image tars, generated SBOM/provenance files, generated checksums, `ARTIFACTS.txt`, output tarballs, and known `/tmp/kubeharbor-*` scratch directories. It does not remove your cert files, installed Docker packages, deployed Harbor runtime, staged `k8s-airgap-images`, or local Docker image cache unless you explicitly request that.

For a full staging-host cleanup after an older run that may have saved Docker credentials under `/root/.docker/config.json`:

```bash
sudo ./tools/clean-airgap-downloads.sh --yes --purge-docker-images --purge-docker-auth
```

Use `--purge-certs` only when you intentionally want to delete files staged under `certs/`.
