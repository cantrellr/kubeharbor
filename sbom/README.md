# kubeharbor air-gap SBOM output

This directory is the staging location for SBOM and provenance metadata generated on the Internet-connected build host before the kubeharbor air-gap tarball is created.

Generated files are intentionally ignored by Git. The committed source of truth is the generator script:

```bash
bash tools/generate-airgap-sbom.sh --repo .
```

The normal bundle workflow calls the generator automatically:

```bash
sudo ./tools/download-airgap-artifacts-on-internet-host.sh
```

Expected generated artifacts include:

| File | Purpose |
| --- | --- |
| `airgap-bundle-manifest.json` | kubeharbor-specific file inventory, hashes, categories, git commit, package metadata, and generation context. |
| `airgap-bundle.spdx.json` | Built-in SPDX 2.3 file-level SBOM generated without external tooling. |
| `airgap-bundle.cyclonedx.json` | Built-in CycloneDX 1.5 file-level SBOM generated without external tooling. |
| `syft-spdx.json` | Optional Syft-generated SPDX SBOM when `syft` is installed. |
| `syft-cyclonedx.json` | Optional Syft-generated CycloneDX SBOM when `syft` is installed. |
| `airgap-bundle-summary.txt` | Human-readable summary for transfer packages and review records. |
| `SHA256SUMS` | Checksums for the generated SBOM files. |

The generated SBOM describes the package payload before compression. It excludes private keys, Docker credentials, `.git`, `output/`, and generated SBOM files themselves.
