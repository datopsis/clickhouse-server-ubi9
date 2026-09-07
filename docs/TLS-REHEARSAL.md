# CA-issued TLS rehearsal

This runbook validates the exact image digest and certificate process before production. It covers connected and disconnected environments, ingress HTTPS/native TLS, outbound public/private trust, renewal, rollback, and negative tests. It does not turn the image repository into a deployment stack; reusable platform manifests and certificate automation belong in `clickhouse-production-stack`.

Never place a private key, CSR containing private material, CA signing key, password, generated certificate, or scanner credential in Git or a GitHub Actions artifact.

## Automated qualification

`tests/tls-rehearsal.sh` creates an ephemeral two-tier CA, issues DNS-specific leaves, and destroys every key and certificate on exit. It runs once per native CI architecture after the normal smoke suite:

```console
CONTAINER_RUNTIME=podman \
  IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9:test \
  bash tests/tls-rehearsal.sh
```

The automated test proves:

- the server receives only its leaf key and leaf-plus-intermediate chain;
- HTTPS accepts the issuing CA and exact DNS name; native TLS accepts the CA and protocol query, while OpenSSL independently verifies the listener certificate's DNS name;
- unrelated CAs, wrong hostnames, clear-text clients, an incomplete chain, and an unreadable leaf key fail;
- a connected CA bundle supports both public PKI and a controlled private-CA ClickHouse endpoint;
- an internal Podman/Docker network is marked `internal`, can reach its controlled private-CA endpoint through ClickHouse, and cannot open a public-IP TCP connection;
- connected and disconnected certificate renewal changes the served serial;
- disconnected rollback restores the recorded prior serial without public access.

The internal-network test is repeatable CI evidence. It does not replace an organization's controlled-media and physically or logically disconnected acceptance rehearsal.

On Windows, Podman Machine file sharing does not preserve a host `chmod 000`,
and an internal network does not expose a published port back to the Windows
host. The script therefore runs disconnected HTTPS from another workload on
the internal network and reports that unreadable-key and served-serial
inspection are deferred to native Linux CI. Those assertions are not skipped
in the native AMD64 or ARM64 GitHub Actions jobs.

## 1. Define the exact test boundary

Record these values in the release-candidate evidence before creating keys:

```console
IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
SERVER_DNS=clickhouse.example.internal
HTTPS_PORT=8443
NATIVE_TLS_PORT=9440
```

Record the image digest, ClickHouse version, UBI version, client versions, Podman client/server versions, DNS zone owner, issuing CA policy, expected trust anchors, permitted egress destinations, certificate owner, renewal deadline, and rollback owner. Use the same DNS name in the CSR, certificate SAN, service record, and client tests.

## 2. Connected preparation and transfer inventory

On an approved connected staging host, verify and export the immutable release:

```console
podman pull "${IMAGE}"
podman image inspect "${IMAGE}" --format '{{.Digest}} {{.Architecture}}'
cosign verify \
  --certificate-identity-regexp='https://github.com/datopsis/clickhouse-server-ubi9/.github/workflows/release.yml@refs/tags/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  "${IMAGE}"
podman save --format oci-archive \
  --output clickhouse-server-ubi9.oci "${IMAGE}"
```

Download the release's `image.spdx.json`, `image.sigstore.json`, and `image.intoto.jsonl`. Export only the public CA roots/intermediates authorized inside the disconnected network. Include offline installers or archives for Podman, OpenSSL, `cosign`, ClickHouse clients, and approved scanner databases when those tools are not already managed inside the boundary.

Create an inventory and hashes:

```console
sha256sum clickhouse-server-ubi9.oci \
  image.spdx.json image.sigstore.json image.intoto.jsonl \
  authorized-ca-bundle.pem > SHA256SUMS
sha256sum --check SHA256SUMS
```

The transfer set must not contain a server private key or any CA private key. Move it through the organization's approved media, malware inspection, custody, and two-person verification process. Record media identifier, sender, recipient, timestamps, and both-side hashes outside this public repository.

## 3. Import and verify inside the disconnected boundary

Copy the transfer set to a controlled staging directory, make it read-only after verification, and run:

```console
sha256sum --check SHA256SUMS
podman load --input clickhouse-server-ubi9.oci
podman image inspect "${IMAGE}" --format '{{.Digest}} {{.Architecture}}'
cosign verify --offline \
  --bundle image.sigstore.json \
  "${IMAGE}"
```

If organizational policy imports through an internal registry, push the verified image there, record the internal digest, and deploy by that digest rather than a transferred tag. Confirm internal DNS resolves `SERVER_DNS` from the client and workload networks without public DNS forwarding.

## 4. Generate the key and CSR offline

Generate the server key inside the disconnected security boundary, preferably in the platform secret-management system or on an encrypted administrative host:

```console
umask 077
openssl req -new -newkey rsa:3072 -nodes \
  -keyout tls.key -out clickhouse.csr \
  -subj "/CN=${SERVER_DNS}" \
  -addext "subjectAltName=DNS:${SERVER_DNS}"
openssl req -in clickhouse.csr -noout -verify -subject \
  -text | grep -A1 'Subject Alternative Name'
```

Send only `clickhouse.csr` to the approved internal/offline CA. The CA returns `tls.crt` with the leaf first and required intermediates afterward. Keep its root in `authorized-ca-bundle.pem`, not in the served chain. Verify before deployment:

```console
openssl x509 -in tls.crt -noout \
  -subject -issuer -serial -dates -ext subjectAltName
openssl verify -CAfile authorized-ca-bundle.pem tls.crt
openssl pkey -in tls.key -pubout -outform pem | sha256sum
openssl x509 -in tls.crt -pubkey -noout | sha256sum
```

The last two hashes must match. Move `tls.key` directly into the secret workflow and securely remove the administrative copy according to policy.

## 5. Configure read-only secret mounts

Copy `container/config.d/tls.example.xml` to the disconnected configuration channel. For rootless Podman, prepare the private key inside its user namespace:

```console
chmod 0444 tls.crt tls.xml
chmod 0400 tls.key
podman unshare chown 101:0 tls.key
```

Mount the certificate chain, private key, and `tls.xml` through separate
read-only bind mounts exactly as shown in [TLS.md](TLS.md). Set
`CLICKHOUSE_PASSWORD_FILE` to a separately mounted password file; do not put
the password directly into a retained runbook or command log. For
Kubernetes/OpenShift, create the TLS Secret from local files, use a ConfigMap
for `tls.xml`, set read-only mounts, and confirm the assigned UID/group can read
the projected key without granting world access.

For outbound private trust, create one reviewed PEM bundle containing only approved roots/intermediates and mount it with `container/config.d/outbound-ca.example.xml`. A connected deployment bundle normally includes public roots plus private roots; a disconnected bundle should omit public roots unless an approved internal service genuinely uses them.

## 6. Prove network isolation

For a local rehearsal, create an internal network and verify its flag:

```console
podman network create --internal clickhouse-disconnected
podman network inspect clickhouse-disconnected --format '{{.Internal}}'
```

The output must be `true`. In the real target environment, also capture firewall/network-policy configuration and demonstrate that the workload cannot resolve or connect to public endpoints. Do not infer isolation merely because a public DNS lookup happens to fail.

Preload a controlled HTTPS endpoint signed by the internal CA on that network. Test from ClickHouse with its actual integration path—for example the `url()` table function—not only with host `curl`. Require the private endpoint to succeed and an external HTTPS URL to fail. Repeat for every production integration because S3, Kafka, LDAP, dictionaries, and remote ClickHouse connections can use different TLS settings.

## 7. Validate ingress and negative cases

From an authorized client using `SERVER_DNS`:

```console
curl --fail --cacert authorized-ca-bundle.pem \
  "https://${SERVER_DNS}:${HTTPS_PORT}/ping"
clickhouse-client --secure --host "${SERVER_DNS}" \
  --port "${NATIVE_TLS_PORT}" \
  --config-file ./client-config.xml \
  --user default --password --query 'SELECT version()'
openssl s_client -connect "${SERVER_DNS}:${HTTPS_PORT}" \
  -servername "${SERVER_DNS}" \
  -CAfile authorized-ca-bundle.pem </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer -serial -dates
```

Retain sanitized output. Then require failures for:

- an unrelated CA bundle;
- a DNS name absent from the SAN;
- HTTP sent to the HTTPS port;
- non-secure native protocol sent to `9440`;
- a chain containing only the leaf;
- a key unreadable by the assigned container identity.

Do not use an insecure client flag to make any negative test pass.

## 8. Renew, roll out, and roll back

Before renewal, record the current certificate serial, SHA-256 fingerprint, expiry, Secret/resource version, and deployment revision. Generate a new key and CSR inside the same boundary; do not reuse the old private key merely for convenience. Validate the returned SAN and chain, create a versioned Secret, and restart or roll out ClickHouse because certificate reload behavior must not be assumed.

After rollout, repeat HTTPS, native TLS, private outbound trust, and isolation tests. Confirm the served serial equals the new serial and differs from the retired one. Keep the old Secret only for the approved rollback window.

For rollback, restore the prior versioned Secret/configuration, perform another controlled restart/rollout, and verify the old recorded serial and database health. A rollback must not restore an expired, revoked, compromised, or policy-prohibited certificate. Remove retired secrets after the rollback window and record destruction.

## 9. Evidence and cleanup

Retain outside Git:

- sanitized commands and timestamps;
- image/internal-registry digests and transfer hashes;
- subjects, issuers, SANs, serials, fingerprints, and expiry dates;
- Podman/platform versions, DNS results, and isolation proof;
- positive and negative HTTPS/native/outbound results;
- renewal and rollback revisions and serials;
- confirmation that no private key entered Git, CI artifacts, logs, or transfer media.

Delete test containers, internal networks, temporary volumes, CSRs, and expired certificate copies. Preserve durable database volumes only according to the test-data retention decision. Never delete an unidentified volume with a wildcard cleanup command.
