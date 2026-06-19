# Air-gap package SBOM and provenance workflow

The kubeharbor Internet-side package build now emits SBOM and provenance metadata for the payload that is compressed, checksummed, and moved into the air-gapped environment.

This follows the same operating model used in `rke2-node-init`: generate traceability while artifacts are still on the connected staging system, move the metadata with the package, and validate it before the offline install mutates the target host.

## Why this matters

The air-gap tarball is the trust boundary. Once it crosses into the disconnected environment, operators need to know what was packaged, which Harbor and DHI versions were intended, which files were included, and whether the package still matches the generated hashes. Without that metadata, the package is just a tarball with good intentions.

## Default behavior

The Internet staging script generates SBOM files by default:

```bash
sudo ./tools/download-airgap-artifacts-on-internet-host.sh
```

Generated metadata is written to `sbom/` before the package tarball is created, so the SBOM directory is included inside the moveable package. The same SBOM directory is also archived externally as:

```text
output/<package-name>-sbom.tgz
output/<package-name>-sbom.tgz.sha256
```

Move these alongside the main package and checksum:

```text
output/<package-name>.tgz
output/<package-name>.tgz.sha256
output/<package-name>-sbom.tgz
output/<package-name>-sbom.tgz.sha256
```

## Generated files

| File | Required | Purpose |
| --- | --- | --- |
| `sbom/airgap-bundle-manifest.json` | Yes | kubeharbor-specific file inventory, SHA256/SHA1 hashes, categories, git commit, package name, Harbor version, DHI image, and generation context. |
| `sbom/airgap-bundle.spdx.json` | Yes | Built-in SPDX 2.3 file-level SBOM generated with Python, no external SBOM tooling required. |
| `sbom/airgap-bundle.cyclonedx.json` | Yes | Built-in CycloneDX 1.5 file-level SBOM generated with Python, no external SBOM tooling required. |
| `sbom/airgap-bundle-summary.txt` | Yes | Human-readable summary for operators and transfer records. |
| `sbom/SHA256SUMS` | Yes | Checksums for generated SBOM/provenance files. |
| `sbom/syft-spdx.json` | Optional | Syft-generated SPDX SBOM when `syft` is installed. |
| `sbom/syft-cyclonedx.json` | Optional | Syft-generated CycloneDX SBOM when `syft` is installed. |

The built-in SPDX/CycloneDX output is intentionally file-level. It gives deterministic package accountability even on a plain Ubuntu staging host. Syft adds richer package/component discovery when available.

## Enforce Syft-generated SBOMs

The default build does **not** require Syft because not every staging host has it installed. To require it:

```bash
sudo REQUIRE_SYFT_FOR_SBOM=true ./tools/download-airgap-artifacts-on-internet-host.sh
```

To let the staging script install Syft to `/usr/local/bin` first:

```bash
sudo INSTALL_SYFT_FOR_SBOM=true REQUIRE_SYFT_FOR_SBOM=true \
  ./tools/download-airgap-artifacts-on-internet-host.sh
```

That command downloads Syft from the upstream Anchore installer. Use it only on the Internet-connected staging host and only if that aligns with your software acquisition policy.

## Generate SBOM only

For testing or review without rebuilding the full air-gap package:

```bash
bash tools/generate-airgap-sbom.sh \
  --repo . \
  --package-name test-kubeharbor-airgap \
  --harbor-version v2.15.1 \
  --dhi-image cantrellcloud/dhi-harbor-portal:2.15.1-debian13
```

To require Syft in this direct workflow:

```bash
sudo bash tools/generate-airgap-sbom.sh \
  --repo . \
  --package-name test-kubeharbor-airgap \
  --harbor-version v2.15.1 \
  --dhi-image cantrellcloud/dhi-harbor-portal:2.15.1-debian13 \
  --install-syft \
  --require-syft
```

## Air-gapped validation

After extracting the main package on the air-gapped VM, validate SBOM integrity before install:

```bash
cd kubeharbor
( cd sbom && sha256sum -c SHA256SUMS )
python3 -m json.tool sbom/airgap-bundle-manifest.json >/dev/null
python3 -m json.tool sbom/airgap-bundle.spdx.json >/dev/null
python3 -m json.tool sbom/airgap-bundle.cyclonedx.json >/dev/null
```

The installer preflight performs the same control gate when this setting is enabled:

```bash
REQUIRE_AIRGAP_SBOM="true"
```

That is now the default in `config/harbor.env`.

## Scope and exclusions

The SBOM describes the repo payload before compression. It excludes:

- `.git/`
- `.docker/`
- `.diagram-tools/`
- `diagrams/node_modules/`
- `output/`
- generated `sbom/` files
- `certs/*.key`
- certificate request/serial leftovers such as `certs/*.csr` and `certs/*.srl`
- local editor/cache files

Public certificate files under `certs/` can be inventoried when present. Private keys are intentionally excluded and should never be shipped in the repo or external SBOM archive.

## Operational contract

For every air-gap transfer, keep these together:

1. Main air-gap package tarball.
2. Main tarball `.sha256` file.
3. External SBOM archive.
4. External SBOM archive `.sha256` file.
5. Transfer approval record or ticket identifier.

No sugar-coating: an SBOM that is generated but not moved with the package is a checkbox artifact. It does not help the offline operator prove what crossed the boundary.
