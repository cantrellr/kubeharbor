# kubeharbor operator runbook

## Start/stop/status

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
sudo docker compose up -d
```

## Validate API

```bash
curl -k https://kubeharbor.dev.kube/api/v2.0/ping
```

## Confirm portal image

```bash
cd /opt/harbor
sudo docker compose images portal
```

## Login/push/pull smoke test

```bash
docker login kubeharbor.dev.kube

docker tag <local-image>:<tag> kubeharbor.dev.kube/library/<local-image>:<tag>
docker push kubeharbor.dev.kube/library/<local-image>:<tag>
docker pull kubeharbor.dev.kube/library/<local-image>:<tag>
```

In a fully air-gapped environment, use an image already present on the staging client instead of pulling from the Internet.

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

