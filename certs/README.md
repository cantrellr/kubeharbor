# TLS certificate staging

Place your production/internal certificates here before running `sudo ./install.sh` on the air-gapped VM.

Expected files:

```text
kubeharbor.dev.kube.crt   # leaf/server certificate for kubeharbor.dev.kube
kubeharbor.dev.kube.key   # leaf/server private key
ca.crt                    # issuing/root CA certificate for client trust distribution
```

Only the three files above are required and supported in this bundle workflow.

The leaf certificate SAN should include:

- `DNS:kubeharbor.dev.kube`
- `DNS:kubeharbor`
- optional IP SAN if clients will use the IP address directly

The install process creates a full-chain file under `/opt/harbor/certs/` by concatenating the leaf cert and `ca.crt` when the CA cert is present.
