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

Harbor startup now defaults to serial orchestration to avoid logger startup races:

1. Start `harbor-log` first.
2. Wait for `127.0.0.1:1514` listener readiness.
3. Start remaining Harbor services.

### What `install.sh` now validates before install proceeds

The preflight step now fails early on common deployment blockers:

- Missing/empty required settings in `config/harbor.env`.
- Placeholder or too-short (`<16`) Harbor admin/DB passwords.
- Harbor installer/version mismatch (`harbor-offline-installer-<version>.tgz` vs `HARBOR_VERSION`).
- `HARBOR_CONFIG_VERSION` mismatch against `HARBOR_VERSION` (without `v`).
- SHA256 mismatches in `installers/`, `images/`, and `packages/docker-debs/`.
- TLS cert/key mismatch, invalid CA chain, or cert hostname mismatch.
- Invalid DHI portal toggle combinations.

For lab-only validation on undersized VMs, you can set:

- `ALLOW_UNDERSIZED_LAB="true"`

This downgrades CPU/RAM baseline failures to warnings. Keep it `false` for production-like installs.

This is intentional: fix preflight errors first, then rerun `sudo ./install.sh`.

### Safer destructive disk behavior

When `FORMAT_DATA_DISK="true"`, the installer now refuses to format if:

- `DATA_DISK_DEVICE` is not a full disk (`TYPE=disk`).
- The selected disk appears to be the OS/root disk.
- Any partition on that disk is currently mounted.

Continue only after validating the target device with `lsblk`.

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

## Service startup behavior

`harbor.service` uses `/usr/local/sbin/harbor-start-serial.sh`, so `systemctl start harbor` follows the same serial log-bootstrap sequence as installer startup.

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

