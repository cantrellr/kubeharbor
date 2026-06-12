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
