# kubeharbor Docker air-gap deployment bundle

This bundle deploys Harbor on a single Ubuntu 24.04 LTS VM named `kubeharbor` using Docker Engine and the Docker Compose plugin.

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

This is viable for a small/internal air-gapped registry. It is not a high-availability design. Treat Harbor as a platform dependency: if it is down, Kubernetes lifecycle work gets painful quickly.

## Recommended DHI image tag

Use the runtime Docker Hardened Image tag that matches the Harbor version deployed by the offline installer:

```bash
cantrellcloud/dhi-harbor-portal:2.15.1-debian
```

Do not use the `-dev` variant as the default steady-state portal image. The `-dev` tag is intended for build/troubleshooting workflows and usually carries a larger runtime footprint. Use it only when you are intentionally debugging or validating the hardened image behavior.

## What the Internet staging script does

Run this on an Internet-connected Ubuntu 24.04 amd64 staging host:

```bash
sudo ./tools/download-airgap-artifacts-on-internet-host.sh
```

The script:

1. Adds the official Docker apt repo on the staging host.
2. Downloads Docker Engine, CLI, containerd, Buildx, Compose plugin, and dependency `.deb` files into `packages/docker-debs/`.
3. Downloads the Harbor offline installer into `installers/`.
4. Prompts for Docker username and password/access token.
5. Runs `docker pull cantrellcloud/dhi-harbor-portal:2.15.1-debian` by default.
6. Saves that image into `images/*.tar`.
7. Generates SHA256 files.
8. Creates one moveable tarball under `output/`.

To override the DHI tag for testing:

```bash
sudo DHI_IMAGE="cantrellcloud/dhi-harbor-portal:2.15.1-debian-dev" \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

## Air-gap deployment flow

On `kubeharbor`:

```bash
tar -xzf kubeharbor-airgap-v2.15.1-<timestamp>.tgz
cd kubeharbor-docker-airgap-bundle-v2
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

For the 500 GB data disk, set one of these paths:

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

## Docker client trust

On every Docker client that will push/pull from Harbor:

```bash
sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt
sudo docker login kubeharbor.dev.kube
```

For RKE2/containerd nodes, configure trust in the RKE2/containerd registry configuration instead of Docker's `/etc/docker/certs.d` path.
## Reset downloaded artifacts / clean slate

Run this on the Internet-connected staging host when you want to purge previously downloaded artifacts and rebuild the air-gap tarball from scratch.

```bash
sudo ./tools/clean-airgap-downloads.sh --dry-run
sudo ./tools/clean-airgap-downloads.sh --yes
```

Default cleanup removes generated/downloaded bundle content only: Docker `.deb` files, Harbor offline installer files, saved Docker image tars, generated checksums, `ARTIFACTS.txt`, output tarballs, and known `/tmp/kubeharbor-*` scratch directories. It does not remove your cert files, installed Docker packages, deployed Harbor runtime, or local Docker image cache unless you explicitly request that.

For a full staging-host cleanup after an older run that may have saved Docker credentials under `/root/.docker/config.json`:

```bash
sudo ./tools/clean-airgap-downloads.sh --yes --purge-docker-images --purge-docker-auth
```

Use `--purge-certs` only when you intentionally want to delete files staged under `certs/`.
