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
| Extra DHI image | `cantrellcloud/dhi-harbor-portal:2.15.1-debian-dev` |

This is viable for a small/internal air-gapped registry. It is not a high-availability design. Treat Harbor as a platform dependency: if it is down, Kubernetes lifecycle work gets painful quickly.

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
5. Runs `docker pull cantrellcloud/dhi-harbor-portal:2.15.1-debian-dev`.
6. Saves that image into `images/*.tar`.
7. Generates SHA256 files.
8. Creates one moveable tarball under `output/`.

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

The bundle always downloads and loads the DHI image when the staging script runs successfully.

By default, Harbor uses the official image set from the Harbor offline installer. To swap only the `portal` service to the DHI image after the official installer runs, set:

```bash
USE_DHI_HARBOR_PORTAL="true"
```

That is intentionally explicit because `dhi-harbor-portal` is one Harbor component, not the entire Harbor deployment stack.

## Docker client trust

On every Docker client that will push/pull from Harbor:

```bash
sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt
sudo docker login kubeharbor.dev.kube
```

For RKE2/containerd nodes, configure trust in the RKE2/containerd registry configuration instead of Docker's `/etc/docker/certs.d` path.
