# TLS certificates and trust

TLS has two independent directions in this image:

- **Ingress TLS** encrypts client connections to ClickHouse. Terminate TLS at a trusted ingress/load balancer, or enable ClickHouse's HTTPS (`8443`) and secure native (`9440`) listeners.
- **Egress TLS trust** lets ClickHouse validate servers that it calls, such as S3-compatible storage, HTTPS dictionaries, URL engines, or remote ClickHouse nodes. Public Internet endpoints normally need no change because the image includes Red Hat's public CA bundle. Private CAs and TLS-inspection proxies require an additional trust bundle.

Do not use a server certificate as an outbound trust anchor, disable certificate verification, put a private key in an image layer, or store it in Git.

Use the step-by-step [CA-issued TLS rehearsal](TLS-REHEARSAL.md) to qualify connected and disconnected deployments, negative cases, renewal, and rollback for an exact image digest.

## Recommended production boundary

Prefer TLS termination at the platform ingress, load balancer, or service mesh when it supports every protocol in use and the network from that proxy to ClickHouse is trusted. This centralizes certificate issuance and rotation. HTTP ingress products commonly cover HTTPS only; the ClickHouse native protocol needs a TCP-capable load balancer, TLS passthrough, or ClickHouse's `tcp_port_secure` listener.

Use ClickHouse termination when end-to-end encryption is required, no suitable TCP proxy exists, or policy requires the application to own its key. The image contains the TLS implementation needed by ClickHouse but intentionally does not generate keys. Generate keys outside the container and mount them read-only.

## Issue an ingress certificate

Use the organization's CA in production. The certificate's Subject Alternative Name must contain every DNS name or IP address clients use. Generate the private key where the container will be deployed when possible, then send only the CSR to the CA:

```console
umask 077
openssl req -new -newkey rsa:3072 -nodes \
  -keyout tls.key -out clickhouse.csr \
  -subj '/CN=clickhouse.example.internal' \
  -addext 'subjectAltName=DNS:clickhouse.example.internal,DNS:clickhouse'
```

Have the CA return `tls.crt` containing the leaf certificate followed by any intermediate certificates. Keep the root CA separate for clients. Verify the result before deployment:

```console
openssl req -in clickhouse.csr -noout -verify
openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName
openssl verify -CAfile organization-ca-bundle.pem tls.crt
```

For a disposable local test only, a self-signed certificate can be made without a CA:

```console
umask 077
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 30 \
  -keyout tls.key -out tls.crt \
  -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
```

## Enable direct TLS with Podman

Copy [`container/config.d/tls.example.xml`](../container/config.d/tls.example.xml) to `tls.xml` beside the certificate and key. It contains:

```xml
<?xml version="1.0"?>
<clickhouse>
    <https_port>8443</https_port>
    <tcp_port_secure>9440</tcp_port_secure>

    <!-- Publish only TLS ports in production. -->
    <http_port remove="remove"/>
    <tcp_port remove="remove"/>

    <openSSL>
        <server>
            <certificateFile>/etc/clickhouse-server/certs/tls.crt</certificateFile>
            <privateKeyFile>/etc/clickhouse-server/certs/tls.key</privateKeyFile>
            <verificationMode>none</verificationMode>
            <loadDefaultCAFile>true</loadDefaultCAFile>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
            <preferServerCiphers>true</preferServerCiphers>
        </server>
    </openSSL>
</clickhouse>
```

`verificationMode` controls whether the server requires client certificates; `none` still provides server-authenticated TLS. Use a reviewed mutual-TLS configuration if client-certificate authentication is required.

The entrypoint detects that the clear-text native port was removed and uses
`tcp_port_secure` for initialization and its local health check. A dedicated,
immutable client configuration skips certificate validation only for that
loopback-only internal query, where a CA-issued server certificate commonly
does not identify `127.0.0.1`. It is not merged into ClickHouse Server's
outbound TLS configuration. External clients and server-side integrations must
validate the certificate, chain, and hostname normally.

For rootless Podman on Linux, map the files to the image identity inside Podman's user namespace and keep the private key unreadable to other container users:

```console
chmod 0444 tls.crt tls.xml
chmod 0400 tls.key
podman unshare chown 101:0 tls.key
```

The key may display subordinate host IDs afterward; `podman unshare ls -l tls.key` shows its container-visible ownership. For rootful Podman, use `sudo chown 101:0 tls.key` instead. Do not make the private key world-readable to bypass a mapping problem.

Run the image with separate read-only mounts. Add `:Z` to bind mounts on SELinux hosts:

```console
podman run --detach --name clickhouse \
  --publish 18443:8443 --publish 19440:9440 \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume clickhouse-data:/var/lib/clickhouse \
  --volume ./tls.xml:/etc/clickhouse-server/config.d/tls.xml:ro,Z \
  --volume ./tls.crt:/etc/clickhouse-server/certs/tls.crt:ro,Z \
  --volume ./tls.key:/etc/clickhouse-server/certs/tls.key:ro,Z \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

`EXPOSE` is image metadata, not a firewall; publishing `8443` and `9440` works even though the image metadata lists the upstream defaults. The example removes ports `8123` and `9000`. Do not publish those clear-text ports when TLS is mandatory. Port `9009` is inter-server HTTP and must remain private; clustered deployments should separately configure `interserver_https_port` and credentials.

Validate both protocols from a client that trusts the issuing CA:

```console
curl --fail --cacert organization-ca-bundle.pem \
  'https://clickhouse.example.internal:18443/ping'

clickhouse-client --secure --host clickhouse.example.internal --port 19440 \
  --user default --password 'replace-me' \
  --config-file ./client-config.xml --query 'SELECT 1'
```

Configure the client's CA according to that client or driver; never use an `insecure` or `skip verification` option as the production solution.

Client behavior must be qualified, not inferred from `verificationMode` alone.
In native-protocol testing with ClickHouse 26.8.2.7, `clickhouse-client` strict
mode rejected an unrelated CA but did not reject the same trusted certificate
when the connection used a different DNS alias. The CI rehearsal therefore
uses `clickhouse-client` to prove native protocol and CA validation, and
OpenSSL's `-verify_hostname` to prove the certificate presented by the native
listener has the expected identity. Confirm that each production driver
performs hostname verification. If a required client does not, tightly scope
CA issuance and network access and treat the limitation as accepted risk, or
terminate native TLS at a proxy that enforces the expected identity.

## Kubernetes and OpenShift secret mount

Create the Secret locally without putting key material in YAML or shell history, then apply it through the approved cluster-management channel:

```console
kubectl create secret tls clickhouse-ingress-tls \
  --cert=tls.crt --key=tls.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap clickhouse-tls-config \
  --from-file=tls.xml \
  --dry-run=client -o yaml | kubectl apply -f -
```

Mount the Secret at `/etc/clickhouse-server/certs` and the ConfigMap file at `/etc/clickhouse-server/config.d/tls.xml`. Use `readOnly: true` and `defaultMode: 0440` for the Secret. The baseline image runs as `101:0`, and OpenShift-compatible arbitrary UIDs normally receive group `0`; confirm the platform security context can read the projected files. A platform ingress Secret is mounted into the ingress controller, not this container.

Restart or perform a controlled rollout after rotation, and test both the new certificate and the old certificate's removal. Automate renewal alerts before expiry. Do not depend on public ACME in a disconnected environment.

## Outbound trust

No extra setup is needed for normally trusted public Internet services. The image ships `/etc/pki/tls/certs/ca-bundle.crt`. Egress should still be allow-listed with a network policy or firewall.

For a private CA, construct one complete PEM bundle outside the container:

- Internet-connected workload: public CA roots plus the organization's root and required intermediate CAs.
- Fully isolated workload: only the internal roots and intermediates that policy authorizes.

Mount that bundle read-only at `/etc/clickhouse-server/certs/outbound-ca-bundle.pem` and copy [`container/config.d/outbound-ca.example.xml`](../container/config.d/outbound-ca.example.xml) to `/etc/clickhouse-server/config.d/outbound-ca.xml`:

```xml
<?xml version="1.0"?>
<clickhouse>
    <openSSL>
        <client>
            <loadDefaultCAFile>false</loadDefaultCAFile>
            <caConfig>/etc/clickhouse-server/certs/outbound-ca-bundle.pem</caConfig>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
            <verificationMode>strict</verificationMode>
            <invalidCertificateHandler>
                <name>RejectCertificateHandler</name>
            </invalidCertificateHandler>
        </client>
    </openSSL>
</clickhouse>
```

This configures the ClickHouse/Poco TLS client with strict validation. Individual integrations can have a separate CA-file setting; point each one at the same bundle and verify it in a staging query. Do not assume one successful HTTPS dictionary test proves S3, Kafka, LDAP, and inter-server TLS all use the same client stack.

An alternative is a derived image with the private CA added to the RHEL trust store:

```dockerfile
FROM ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<verified-digest>
USER 0
COPY organization-root-ca.pem /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust
USER 101:0
```

Build this only from a reviewed context, keep the CA certificate (never a private CA key) in the context, scan the derived image, and sign it under the deploying organization's identity. Rebuild when either the upstream image or CA set changes.

## Disconnected deployment

An offline network changes delivery, not TLS fundamentals:

1. On a connected staging system, pull the image by digest, verify its signature and release evidence, export it as an OCI or Docker archive, and scan it with vulnerability databases approved for transfer.
2. Transfer the image archive, SBOM, signature bundle, scanner database snapshot, and public verification material through the organization's controlled media process. Record hashes on both sides. Import the image into the disconnected registry; deploy by its internal digest.
3. Generate the server private key inside the disconnected security boundary. Send a CSR to the offline/internal CA and return the signed leaf plus chain. Never move the CA private key to the workload and avoid moving the server private key at all.
4. Distribute the internal root CA to every client and create the ingress Secret or read-only mounts described above. Configure an internal certificate-renewal owner and calendar; public ACME and public revocation endpoints will not be reachable.
5. Build the outbound bundle from only the internal trust anchors needed in that network. Test every allowed destination by DNS name, confirm time synchronization, and deny all other egress.
6. Rehearse renewal, revocation, image update, backup restoration, and rollback without Internet access before production approval.

The [ClickHouse TLS guide](https://clickhouse.com/docs/guides/sre/tls/configuring-tls) documents secure HTTP, native, inter-server, and Keeper channels. Red Hat documents the [RHEL 9 shared trust store](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/securing_networks/using-shared-system-certificates_securing-networks).
