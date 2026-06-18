# k8s-airgap-images integration

`k8s-airgap-images` is the image acquisition and promotion utility used by kubeharbor for large Kubernetes platform image sets. kubeharbor owns the Harbor VM, Docker runtime placement, TLS trust, Harbor deployment, and registry lifecycle. `k8s-airgap-images` owns image-list normalization, registry credential prompting, upstream image pulls, deterministic retagging, Harbor project preflight, and push logging.

This separation is intentional. Harbor should not also be the canonical owner of every platform image list. The registry platform and the image acquisition catalog have different lifecycles, different failure modes, and different change velocity.

## What it is

`k8s-airgap-images` is a standalone repository that contains:

- source image lists under `source-lists/`;
- a Python organizer that normalizes and categorizes upstream images;
- generated image lists under `image-lists/`;
- pull and push wrapper scripts;
- a main `image-airgap.sh` CLI;
- logs for pull success, pull failures, push success, push failures, missing local images, and source-to-target image mapping.

The repo replaces the older `image-airgap-bundle-updated.zip` workflow. The ZIP path is deprecated because it made the image catalog feel like a one-off artifact instead of a versioned operational source of truth.

## What it is used for

Use `k8s-airgap-images` when the kubeharbor VM must acquire and later promote container images for disconnected Kubernetes environments. The common workloads include RKE2 dependencies, Rancher, Argo CD, Istio, Kiali, monitoring, ingress controllers, platform utilities, and other application bundles that need to be pulled from upstream registries before entering an air gap.

The primary use cases are:

1. **Internet-side acquisition**: pull all required upstream images while the VM still has Internet access.
2. **Credential separation**: prompt separately for Docker Hub, Iron Bank, DHI, and other authenticated registries.
3. **Image-list governance**: normalize source image lists and keep generated lists reproducible.
4. **VM clone transfer**: keep pulled image layers under `/data/docker` so the cache travels with the VM clone.
5. **Air-gap promotion**: retag cached images and push them into `kubeharbor.dev.kube` or another internal Harbor endpoint.
6. **Harbor project reconciliation**: create or verify target Harbor projects before push when credentials allow it.

## How kubeharbor uses it

kubeharbor stages the repository under `/data/k8s-airgap-images` with:

```bash
sudo ./tools/install-k8s-airgap-images.sh \
  --source https://github.com/cantrellr/k8s-airgap-images.git \
  --replace
```

The staging script also creates convenience symlinks:

```text
/opt/k8s-airgap-images
/opt/kubeharbor-image-transfer
```

The canonical location is `/data/k8s-airgap-images`. The `/opt/kubeharbor-image-transfer` symlink is only there for compatibility with older operator habits.

kubeharbor then calls the staged utility through wrapper scripts:

```bash
sudo ./tools/pull-images-to-data-cache.sh
sudo ./tools/push-data-cache-to-harbor.sh --target kubeharbor.dev.kube/library
```

The wrappers do not own image-list logic. They locate the compatible CLI inside the staged repo, enforce kubeharbor storage guardrails, and pass the request through to `k8s-airgap-images`.

## How it works

### 1. Source lists are normalized

Input files under `source-lists/` may contain images from Docker Hub, Iron Bank, DHI, NGINX, GitHub Container Registry, Quay, or other registries. The organizer normalizes image names by adding `docker.io/` when an image does not explicitly specify a registry.

The organizer then writes generated lists under `image-lists/`:

| Generated list | Purpose |
| --- | --- |
| `00-public-images.list` | Public/no-auth images. |
| `10-docker-hardened-images.list` | DHI-style images such as `dhi.io/*` and `docker.io/*/dhi-*`. |
| `20-registry1-dso-mil-images.list` | Iron Bank images from `registry1.dso.mil`. |
| `30-nginx-registry-images.list` | NGINX private registry images. |
| `archived-images.list` | Bitnami images removed from the active workflow. |
| `all-active-images.list` | Union of all non-archived images. |
| `all-source-images.list` | All unique normalized source images. |
| `manifest-counts.txt` | Counts by category for review. |

### 2. Pull workflow runs before the VM enters the air gap

The pull workflow prompts for registry credentials and pulls images into the local Docker cache. kubeharbor configures Docker so that cache is backed by `/data/docker`, not the OS disk.

```bash
sudo ./tools/pull-images-to-data-cache.sh
```

Useful logs are written under:

```text
/data/k8s-airgap-images/logs
```

Review pull failures before cloning the VM. If the cache is incomplete, the air-gapped VM will not be able to magically recover missing upstream layers.

### 3. VM clone/move carries the cache

After the pull workflow completes, the VM can be cloned and moved or re-IP'd into the disconnected environment. The key design point is that Docker's data root remains under `/data/docker`, so the local cache moves with the VM clone.

Do not run `docker system prune` before cloning. That is how you convert a working air-gap plan into a bad afternoon.

### 4. Push workflow promotes cached images into Harbor

On the air-gapped clone, the push workflow retags cached source images and pushes them into Harbor:

```bash
sudo ./tools/push-data-cache-to-harbor.sh --target kubeharbor.dev.kube/library
```

The default mode is `strip-registry`, which removes the upstream registry hostname from the target path. For example:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

Use `preserve-registry` when collision avoidance matters more than clean internal paths:

```text
docker.io/rancher/rancher:v2.14.2
  -> kubeharbor.dev.kube/library/docker.io/rancher/rancher:v2.14.2
```

### 5. Harbor project preflight runs before push

When enabled, the push workflow checks the target Harbor projects and creates missing projects if the Harbor API credentials allow it. Push-only robot accounts often cannot create projects. Use a project-management account for preflight when project creation is required, then use robot accounts for scoped automation pushes where appropriate.

## Ownership boundary

| Capability | kubeharbor | k8s-airgap-images |
| --- | --- | --- |
| Harbor installation | Owns | Does not own |
| Docker storage root under `/data` | Owns | Consumes |
| TLS and client trust | Owns | Requires working trust |
| Source image catalog | References | Owns |
| Image normalization | Does not own | Owns |
| Registry credential prompts | Delegates | Owns |
| Pull/push retries and logs | Delegates | Owns |
| Harbor project preflight | Delegates | Owns via Harbor API |
| VM clone transfer model | Owns | Participates |

## Validation checklist

Before entering the air gap:

```bash
sudo docker info --format '{{.DockerRootDir}}'
ls -lah /data/k8s-airgap-images/image-lists
ls -lah /data/k8s-airgap-images/logs
cat /data/k8s-airgap-images/logs/pull-failed-*.list 2>/dev/null || true
```

After pushing into Harbor:

```bash
ls -lah /data/k8s-airgap-images/logs
cat /data/k8s-airgap-images/logs/push-failed-*.list 2>/dev/null || true
cat /data/k8s-airgap-images/logs/push-missing-local-*.list 2>/dev/null || true
docker pull kubeharbor.dev.kube/library/rancher/rancher:v2.14.2
```

## Hard rules

- Keep `k8s-airgap-images` under `/data`, not the OS disk.
- Treat `source-lists/` as governed input, not scratch-pad noise.
- Regenerate `image-lists/` after changing source lists.
- Do not copy Docker layer files directly into Harbor registry storage.
- Promote images through the registry API by retagging and pushing.
- Do not assume robot accounts can create Harbor projects.
- Do not continue using `image-airgap-bundle-updated.zip` for new workflows.
