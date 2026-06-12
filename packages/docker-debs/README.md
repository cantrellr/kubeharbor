# Docker offline package staging

The Internet-connected staging script downloads Docker Engine and dependency `.deb` files here for offline installation on Ubuntu 24.04 LTS x86_64.

Expected core package set includes:

- `containerd.io_*.deb`
- `docker-ce_*.deb`
- `docker-ce-cli_*.deb`
- `docker-buildx-plugin_*.deb`
- `docker-compose-plugin_*.deb`

The script also attempts to collect required dependencies so the air-gapped VM can install Docker without Internet access.
