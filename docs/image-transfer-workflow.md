# Internet-to-airgap image transfer workflow

This workflow is for the VM-clone model using the `k8s-airgap-images` repository as the image-list and pull/push utility source.

The old `image-airgap-bundle-updated.zip` workflow is deprecated. Do not build new procedures around that ZIP. Use `k8s-airgap-images` as the source of truth for image lists, registry-auth handling, pull logs, push logs, and retag/push behavior.

## What `k8s-airgap-images` is

`k8s-airgap-images` is a standalone image acquisition and promotion repository. It is not Harbor, and it is not part of the Harbor installer. It is the operational catalog and tooling layer used to pull upstream Kubernetes platform images while Internet-connected and then push those cached images into Harbor after the VM is moved into the air gap.

The repo owns:

- source image lists under `source-lists/`;
- generated normalized lists under `image-lists/`;
- image categorization for public, DHI, Iron Bank, NGINX private, archived Bitnami, and all active images;
- registry credential prompts for pull workflows;
- deterministic retagging for push workflows;
- Harbor project preflight and optional project creation;
- pull, push, missing-image, and source-to-target mapping logs.

kubeharbor owns the registry platform. `k8s-airgap-images` owns the image catalog and transfer behavior. That split is deliberate because registry lifecycle and image-catalog lifecycle do not move at the same pace.

Full background is in [k8s-airgap-images Integration](k8s-airgap-images-integration.md).

## Workflow summary

1. Build/deploy Harbor on an Internet-connected VM with the kubeharbor repo.
2. Stage the `k8s-airgap-images` repository under `/data/k8s-airgap-images`.
3. Organize source image lists into normalized generated lists.
4. Pull all required upstream images into the local Docker cache while the VM still has Internet access.
5. Clone the VM.
6. Re-IP/move the clone into the air-gapped environment.
7. Push the locally cached images into the reachable air-gapped Harbor registry.
8. Validate a representative pull from Harbor.

## Storage model

The VM has a 64 GB OS disk and a 500 GB data disk. Do not let large image workflows land under `/var/lib/docker` on the OS disk.

The kubeharbor defaults are:

```bash
DOCKER_DATA_ROOT="/data/docker"
CONTAINERD_ROOT="/data/containerd"
IMAGE_TRANSFER_ROOT="/data/k8s-airgap-images"
```

Docker's `DockerRootDir` must report a path under `/data` before pulling the large image list.

```bash
sudo docker info --format '{{.DockerRootDir}}'
```

Expected:

```text
/data/docker
```

## Stage `k8s-airgap-images` onto `/data`

Clone, copy, or transfer the `k8s-airgap-images` repo to the Internet-connected kubeharbor VM. Then stage it into the `/data` working location:

```bash
cd /path/to/kubeharbor
sudo ./tools/install-k8s-airgap-images.sh /path/to/k8s-airgap-images --replace
```

The installer also accepts a `.tgz`, `.tar.gz`, `.tar`, `.zip`, or Git URL source:

```bash
sudo ./tools/install-k8s-airgap-images.sh /transfer/k8s-airgap-images.tgz --replace

sudo ./tools/install-k8s-airgap-images.sh \
  --source https://github.com/cantrellr/k8s-airgap-images.git \
  --replace
```

Source precedence is deterministic:

1. Explicit positional source argument.
2. `--source <path-or-url>`.
3. Caller-provided `K8S_AIRGAP_IMAGES_SOURCE` environment variable.
4. `K8S_AIRGAP_IMAGES_SOURCE` from `config/harbor.env`.
5. Common local source paths.

Caller environment overrides still work, even when `config/harbor.env` has an empty default:

```bash
sudo K8S_AIRGAP_IMAGES_SOURCE=https://github.com/cantrellr/k8s-airgap-images.git \
  ./tools/install-k8s-airgap-images.sh --replace
```

The staged repo lands here:

```text
/data/k8s-airgap-images
```

and the installer creates these convenience symlinks:

```text
/opt/k8s-airgap-images
/opt/kubeharbor-image-transfer
```

The second symlink is a compatibility alias for older operator habits. The new canonical path is `/data/k8s-airgap-images`.

## Organize image lists

Before a pull, `k8s-airgap-images` organizes source lists into generated lists. kubeharbor normally calls this automatically through the pull wrapper, but it is useful to know what happens.

The organizer reads `source-lists/*.list` and `source-lists/*.txt`, normalizes Docker Hub references with a `docker.io/` prefix, removes Bitnami images from the active workflow, and writes generated lists under `image-lists/`.

Review the generated manifest before the first major pull:

```bash
sudo /data/k8s-airgap-images/organize-image-lists.sh
cat /data/k8s-airgap-images/image-lists/manifest-counts.txt
```

## Pull images while Internet-connected

Run:

```bash
cd /path/to/kubeharbor
sudo ./tools/pull-images-to-data-cache.sh
```

To pull a specific list from the staged `k8s-airgap-images` repo:

```bash
sudo ./tools/pull-images-to-data-cache.sh --list image-lists/all-active-images.list
```

The wrapper locates a compatible CLI inside the staged repo. Supported CLI names are:

```text
image-airgap.sh
k8s-airgap-images.sh
airgap-images.sh
```

If the repo uses a non-standard location, set `K8S_AIRGAP_IMAGES_CLI` in `config/harbor.env` or pass it through the environment.

The underlying `k8s-airgap-images` utility owns registry credential prompts and image-list semantics. kubeharbor's wrapper only enforces the storage guardrails and passes through the pull request.

Pull logs are written under:

```text
/data/k8s-airgap-images/logs
```

Check failures before cloning:

```bash
ls -lah /data/k8s-airgap-images/logs
cat /data/k8s-airgap-images/logs/pull-failed-*.list 2>/dev/null || true
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
ls -lah /data/k8s-airgap-images/logs
cat /data/k8s-airgap-images/logs/push-failed-*.list 2>/dev/null || true
cat /data/k8s-airgap-images/logs/push-missing-local-*.list 2>/dev/null || true
```

Also verify a representative pull from Harbor:

```bash
docker pull kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

## Critical notes

- Harbor does not ingest Docker image tar files by copying them into `/data/registry`. Images must be pushed through the registry API.
- The Internet-connected VM can act as the acquisition/cache node. The air-gapped clone can act as the promotion node.
- If the Internet-connected VM is also a Harbor VM and you push images into Harbor before cloning, then the registry data under `/data` also travels with the clone. In that case, a second push may be unnecessary. The push utility is for the local-Docker-cache-to-Harbor promotion model.
- Keep `k8s-airgap-images` under `/data`; putting it on the OS disk defeats the point of the VM storage split.
- Treat source image-list changes as governed platform changes. A single added image can create new upstream registry authentication, storage, and licensing implications.
