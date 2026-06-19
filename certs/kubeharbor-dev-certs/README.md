# KubeHarbor Fake Development Certificates

These files are intentionally fake and are only for local development or disposable test environments.
Do not use them in production, shared lab infrastructure, customer systems, or any environment where trust matters.

## Included files

- `ca.dev.local.crt` - fake development CA certificate, public certificate only
- `kubeharbor.dev.local.crt` - fake Harbor server certificate signed by the fake CA
- `kubeharbor.dev.local.key` - fake Harbor server private key
- `VERIFY.txt` - OpenSSL verification output and certificate details
- `openssl-ca.cnf` - CA generation config used to create the fake CA
- `openssl-server.cnf` - server certificate config with SANs

## Server certificate identity

The server certificate is issued to:

- Common Name: `kubeharbor.dev.local`
- SAN DNS: `kubeharbor.dev.local`
- SAN DNS: `localhost`
- SAN IP: `127.0.0.1`

## Example validation

```bash
openssl verify -CAfile ca.dev.local.crt kubeharbor.dev.local.crt
openssl x509 -in kubeharbor.dev.local.crt -noout -subject -issuer -dates -ext subjectAltName
```

## Example Harbor placement

For dev/test only, these could be staged in a repo or copied into a local Harbor TLS directory such as:

```text
certs/
  ca.dev.local.crt
  kubeharbor.dev.local.crt
  kubeharbor.dev.local.key
```

Then point the Harbor configuration at the server cert/key and distribute the CA cert only to test clients that need to trust this fake endpoint.
