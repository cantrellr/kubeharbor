# kubeharbor operator runbook

## Start/stop/status

Harbor now starts with serial orchestration by default: `harbor-log` is started first, the local syslog listener on `127.0.0.1:1514` is validated, and then remaining services are started.

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
- Preserves Harbor data under `/data`.

## Validate API

```bash
curl -k https://kubeharbor.dev.kube/api/v2.0/ping
```

## Preflight checks now enforced by installer

`sudo ./install.sh` now fails early when critical checks fail. Current enforced checks include:

- Required settings in `config/harbor.env` are empty.
- Password placeholders remain or admin/DB passwords are shorter than 16 chars.
- Harbor installer filename does not match `HARBOR_VERSION`.
- `HARBOR_CONFIG_VERSION` does not match `HARBOR_VERSION` without `v` prefix.
- SHA256 checksum mismatch in `installers/`, `images/`, or `packages/docker-debs/`.
- TLS leaf cert/key mismatch, CA chain verification failure, or hostname mismatch in cert SAN/CN.
- `USE_DHI_HARBOR_PORTAL=true` with incompatible image-loading settings.

If preflight fails, fix the reported item and rerun `sudo ./install.sh`.

## Disk formatting safety

When `FORMAT_DATA_DISK=true`, installer safeguards now block formatting if:

- `DATA_DISK_DEVICE` is not a full disk device.
- The selected disk appears to be the root OS disk.
- Any partition on the selected disk is mounted.

Always validate with `lsblk` before confirming the format prompt.

## Confirm portal image

```bash
cd /opt/harbor
sudo docker compose images portal
```

Expected default DHI image:

```bash
cantrellcloud/dhi-harbor-portal:2.15.1-debian
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

`scripts/10-verify.sh` now checks:

- Required Harbor services are running.
- HTTPS API ping with retries.
- Optional authenticated API check using `admin` credentials.

If verification reports warnings, inspect logs before promoting the host for production use:

```bash
cd /opt/harbor
sudo docker compose ps
sudo docker compose logs --tail=300
sudo ls -lah /var/log/harbor
```

## Backup

```bash
sudo ./scripts/09-backup-harbor.sh /backup
```

## Common break/fix

### Docker clients fail with x509 unknown authority

Install the internal CA on the client:

```bash
sudo ./scripts/08-install-client-docker-ca.sh kubeharbor.dev.kube /path/to/ca.crt
```

### Harbor containers are restarting

```bash
cd /opt/harbor
sudo docker compose ps
sudo docker compose logs --tail=300
sudo ls -lah /var/log/harbor
```

### Disk full

Check both Docker and Harbor data paths:

```bash
df -h
sudo du -xh /data | sort -h | tail -30
sudo docker system df
```

Do not blindly prune Docker on a production Harbor host. Validate what is safe first.

## Notes from first Internet-connected staging run

The first staging run showed the correct end-state: Docker packages were downloaded, the Harbor offline installer was downloaded, the DHI portal image was pulled and saved, and a moveable air-gap tarball was created.

Changes added in bundle v3:

- Optional Harbor signature/checksum sidecar downloads are probed before fetch. If a sidecar does not exist for the release, the script now reports a controlled warning instead of printing a raw `curl: (22) 404`.
- Docker registry login now uses an ephemeral `DOCKER_CONFIG` under `/tmp` and deletes it on exit. This prevents credentials from being persisted in `/root/.docker/config.json` when running the staging script with `sudo`.
- The apt download scratch directory is world-writable under `/tmp` during package download to reduce `_apt` sandbox warnings. The warnings were not fatal, but they cluttered the output.

## Clean slate before another Internet-connected staging run

Use this before rerunning the artifact downloader when you want a known-clean package state.

```bash
sudo ./tools/clean-airgap-downloads.sh --dry-run
sudo ./tools/clean-airgap-downloads.sh --yes
```

The default cleanup is intentionally scoped to downloaded/generated files inside the bundle and `/tmp/kubeharbor-*` staging directories. To also remove the pulled DHI image from the staging host Docker cache and remove Docker auth left from older runs:

```bash
sudo ./tools/clean-airgap-downloads.sh --yes --purge-docker-images --purge-docker-auth
```

Do not use `--purge-certs` unless you are deliberately deleting staged certificate material.
