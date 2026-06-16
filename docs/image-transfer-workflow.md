# Internet-to-airgap image transfer workflow

This workflow is for the VM-clone model:

1. Build/deploy Harbor on an Internet-connected VM with the kubeharbor repo.
2. Extract the supplied `image-airgap-bundle-updated.zip` under `/data`.
3. Pull all required upstream images into the local Docker cache while the VM still has Internet access.
4. Clone the VM.
5. Re-IP/move the clone into the air-gapped environment.
6. Push the locally cached images into the reachable air-gapped Harbor registry.

## Storage model

The VM has a 64 GB OS disk and a 500 GB data disk. Do not let large image workflows land under `/var/lib/docker` on the OS disk.

The kubeharbor defaults are:

```bash
DOCKER_DATA_ROOT="/data/docker"
CONTAINERD_ROOT="/data/containerd"
IMAGE_TRANSFER_ROOT="/data/kubeharbor-image-transfer"
```

Docker's `DockerRootDir` must report a path under `/data` before pulling the large image list.

```bash
sudo docker info --format '{{.DockerRootDir}}'
```

Expected:

```text
/data/docker
```

## Install the image list bundle onto `/data`

Copy `image-airgap-bundle-updated.zip` to the VM, then run:

```bash
cd /path/to/kubeharbor
sudo ./tools/install-image-airgap-bundle.sh /path/to/image-airgap-bundle-updated.zip --replace
```

This extracts the image pull/push utility to:

```text
/data/kubeharbor-image-transfer
```

and creates this convenience symlink:

```text
/opt/kubeharbor-image-transfer
```

## Pull images while Internet-connected

Run:

```bash
cd /path/to/kubeharbor
sudo ./tools/pull-images-to-data-cache.sh
```

The underlying image-airgap utility will prompt for credentials for Docker Hub, registry1.dso.mil, dhi.io when applicable, and docker-registry.nginx.com when applicable. You can skip a credential gate if the image list you are pulling does not require that registry.

Pull logs are written under:

```text
/data/kubeharbor-image-transfer/logs
```

Check failures before cloning:

```bash
ls -lah /data/kubeharbor-image-transfer/logs
cat /data/kubeharbor-image-transfer/logs/pull-failed-*.list 2>/dev/null || true
```

## Clone and re-IP

After the pull is complete, clone the VM and move/re-IP the clone into the air-gapped environment. Because Docker/containerd storage is under `/data`, the local image cache travels with the VM clone.

Do not prune Docker before cloning.

## Push cached images into air-gapped Harbor

On the air-gapped clone, make sure Harbor is reachable and the target project exists. The default target is:

```text
kubeharbor.dev.kube/library
```

Then run:

```bash
cd /path/to/kubeharbor
sudo ./tools/push-data-cache-to-harbor.sh
```

To override the target:

```bash
sudo ./tools/push-data-cache-to-harbor.sh --target kubeharbor.dev.kube/library
```

Default push mode is `strip-registry`:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

Use `preserve-registry` only when you need collision avoidance:

```bash
sudo ./tools/push-data-cache-to-harbor.sh --mode preserve-registry --target kubeharbor.dev.kube/library
```

That maps:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/docker.io/rancher/rancher:v2.14.2
```

## Validation

After pushing, review:

```bash
ls -lah /data/kubeharbor-image-transfer/logs
cat /data/kubeharbor-image-transfer/logs/push-failed-*.list 2>/dev/null || true
cat /data/kubeharbor-image-transfer/logs/push-missing-local-*.list 2>/dev/null || true
```

Also verify a representative pull from Harbor:

```bash
docker pull kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

## Critical notes

- Harbor does not ingest Docker image tar files by copying them into `/data/registry`. Images must be pushed through the registry API.
- The Internet-connected VM can act as the acquisition/cache node. The air-gapped clone can act as the promotion node.
- If the Internet-connected VM is also a Harbor VM and you push images into Harbor before cloning, then the registry data under `/data` also travels with the clone. In that case, a second push may be unnecessary. The push utility is for the local-Docker-cache-to-Harbor promotion model.
