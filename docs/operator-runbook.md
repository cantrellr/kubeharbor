# kubeharbor operator runbook

## Start/stop/status

Harbor starts with serial orchestration by default: `harbor-log` is started first, the local syslog listener on `127.0.0.1:1514` is validated, and then remaining services are started.

```bash
sudo systemctl status harbor
sudo systemctl stop harbor
sudo systemctl start harbor

cd /opt/harbor
sudo docker compose ps
sudo docker compose logs -f --tail=200
```

## Reconfigure Harbor after changing harbor.yml

```bash
cd /opt/harbor
sudo docker compose down
sudo ./prepare
sudo /usr/local/sbin/harbor-start-serial.sh
```

## Clean Harbor deployment runtime (keep images and data)

Use this to remove Harbor runtime resources without deleting local Docker images or Harbor data under `/data`.

```bash
sudo /usr/local/sbin/harbor-reset.sh --dry-run
sudo /usr/local/sbin/harbor-reset.sh --yes
sudo /usr/local/sbin/harbor-reset.sh --yes --remove-volumes
```

What it does:

- Runs `docker compose down` in `/opt/harbor`.
- Removes Harbor containers and compose networks.
- Optionally removes Harbor compose volumes when `--remove-volumes` is passed.
- When `--remove-volumes` is passed, also removes `/data/database`.
- Preserves local Docker image cache.
- Preserves Harbor registry data under `/data` unless explicitly removed by a separate operator action.

## Validate API

```bash
curl -k https://kubeharbor.dev.kube/api/v2.0/ping
```

## Preflight checks enforced by installer

`sudo ./install.sh` fails early when critical checks fail. Current enforced checks include:

- Required settings in `config/harbor.env` are empty.
- Password placeholders remain or admin/DB passwords are shorter than 16 chars.
- SBOM/provenance metadata is missing or invalid when `REQUIRE_AIRGAP_SBOM=true`.
- Harbor installer filename does not match `HARBOR_VERSION`.
- `HARBOR_CONFIG_VERSION` does not match `HARBOR_VERSION` without `v` prefix.
- SHA256 checksum mismatch in `sbom/`, `installers/`, `images/`, or `packages/docker-debs/`.
- TLS leaf cert/key mismatch, CA chain verification failure, or cert hostname mismatch in cert SAN/CN.
- `USE_DHI_HARBOR_PORTAL=true` with incompatible image-loading settings.

If preflight fails, fix the reported item and rerun `sudo ./install.sh`.

## SBOM validation before install

The Internet-side staging script generates SBOM and provenance files under `sbom/`. Validate those files before install when reviewing a transferred package:

```bash
( cd sbom && sha256sum -c SHA256SUMS )
python3 -m json.tool sbom/airgap-bundle-manifest.json >/dev/null
python3 -m json.tool sbom/airgap-bundle.spdx.json >/dev/null
python3 -m json.tool sbom/airgap-bundle.cyclonedx.json >/dev/null
```

The installer performs the same control gate by default:

```bash
REQUIRE_AIRGAP_SBOM="true"
```

Set it to `false` only when intentionally installing from a legacy package that predates SBOM support. That should be a documented exception, not the new normal.

## Disk formatting safety

When `FORMAT_DATA_DISK=true`, installer safeguards block formatting if:

- `DATA_DISK_DEVICE` is not a full disk device.
- The selected disk appears to be the root OS disk.
- Any partition on that disk is mounted.

Always validate with `lsblk` before confirming the format prompt.

## Confirm portal image

```bash
cd /opt/harbor
sudo docker compose images portal
```

Expected default DHI image:

```bash
cantrellcloud/dhi-harbor-portal:2.15.1-debian13
```

When `USE_DHI_HARBOR_PORTAL=true`, the override script patches Harbor's generated portal `nginx.conf` for DHI's 8080/non-root runtime model, removes forced portal user overrides, validates the nginx config inside the DHI image, recreates only the portal service, and rolls back if the portal does not remain healthy.

If portal restarts, check quickly:

```bash
cd /opt/harbor
sudo docker compose ps portal
sudo docker logs --tail=100 harbor-portal
sudo docker inspect harbor-portal --format 'status={{.State.Status}} restart={{.RestartCount}} user={{.Config.User}} image={{.Config.Image}}'
```

Fast rollback to the official Harbor portal image:

```bash
cd /opt/harbor
latest_backup="$(ls -1t docker-compose.yml.before-dhi-portal-* | head -1)"
sudo cp "$latest_backup" docker-compose.yml
sudo docker compose up -d
```

## Login/push/pull smoke test

```bash
docker login kubeharbor.dev.kube

docker tag <local-image>:<tag> kubeharbor.dev.kube/library/<local-image>:<tag>
docker push kubeharbor.dev.kube/library/<local-image>:<tag>
docker pull kubeharbor.dev.kube/library/<local-image>:<tag>
```

In a fully air-gapped environment, use an image already present on the staging client instead of pulling from the Internet.

## Verification behavior after install
