# ClickHouse Server on Red Hat UBI 9

A minimal, security-oriented ClickHouse Server container image built on Red Hat Universal Base Image 9 Micro.

This is an independent Datopsis packaging project. It is not an official ClickHouse image and is not affiliated with or endorsed by ClickHouse, Inc. ClickHouse is a trademark of ClickHouse, Inc.

## Security properties

- Red Hat UBI 9 Micro runtime, pinned by multi-architecture digest
- Official ClickHouse release archives, pinned by version and verified with the published SHA-512 checksums
- No package manager or package download utility in the runtime image
- Runs as the non-root `clickhouse` user (`101:0`)
- Compatible with a read-only root filesystem
- Requires no Linux capabilities for its baseline configuration
- Restricts the default user to localhost unless a password is supplied
- CI smoke tests and blocking Trivy scans for fixed high and critical vulnerabilities
- Multi-architecture release images for `linux/amd64` and `linux/arm64`
- Keyless Cosign signatures, SBOM attestations, and build provenance on tagged releases

The builder uses UBI Minimal and is discarded. Only UBI Micro, a small set of UBI runtime packages, ClickHouse, and the entrypoint are present in the published image.

## Quick start

```console
docker run --detach \
  --name clickhouse \
  --publish 18123:8123 \
  --publish 19000:9000 \
  --ulimit nofile=262144:262144 \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only \
  --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --volume clickhouse-data:/var/lib/clickhouse \
  ghcr.io/datopsis/clickhouse-server-ubi9:<release-tag>
```

Then query it with a ClickHouse client:

```console
clickhouse-client --host 127.0.0.1 --port 19000 \
  --user default --password 'replace-me' \
  --query 'SELECT version()'
```

The included `compose.yaml` provides the same hardened local baseline. Change its example password before use.

## Configuration

| Variable | Purpose | Default |
| --- | --- | --- |
| `CLICKHOUSE_PASSWORD` | Password for the `default` user; enables network access | Empty; localhost only |
| `CLICKHOUSE_PASSWORD_FILE` | Read the default-user password from a mounted secret | Unset |
| `CLICKHOUSE_DB` | Create this database on the first start | Unset |
| `CLICKHOUSE_INIT_TIMEOUT` | Seconds to wait for the temporary initialization server | `60` |
| `CLICKHOUSE_ALWAYS_RUN_INITDB_SCRIPTS` | Run initialization scripts on every start when non-empty | Unset |
| `CLICKHOUSE_CONFIG` | Main server configuration file | `/etc/clickhouse-server/config.xml` |
| `CLICKHOUSE_DATA_DIR` | Data and generated-configuration directory | `/var/lib/clickhouse` |

The image intentionally manages only the built-in `default` user through environment variables. Create additional users with SQL or mounted ClickHouse configuration.

Mount configuration fragments under:

- `/etc/clickhouse-server/config.d/*.xml`
- `/etc/clickhouse-server/users.d/*.xml`

Place first-start initialization files in `/docker-entrypoint-initdb.d`. Executable and sourced `.sh`, `.sql`, and `.sql.gz` files are supported and processed in lexical order.

Persistent data belongs at `/var/lib/clickhouse`. The image writes generated user configuration there, allowing the root filesystem to remain read-only.

## Build and test

Docker:

```console
docker build --file Containerfile \
  --tag ghcr.io/datopsis/clickhouse-server-ubi9:test .
IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9:test bash tests/smoke.sh
```

Podman uses OCI format by default, which omits Docker health-check metadata. Use Docker image format when building locally:

```console
podman build --format docker --file Containerfile \
  --tag ghcr.io/datopsis/clickhouse-server-ubi9:test .
CONTAINER_RUNTIME=podman \
  IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9:test \
  bash tests/smoke.sh
```

Build-time arguments are `CLICKHOUSE_VERSION`, `CLICKHOUSE_CHANNEL`, `UBI_MINIMAL_IMAGE`, and `UBI_MICRO_IMAGE`. Release builds should retain immutable UBI digests and an exact ClickHouse version.

## Release process

1. Update and locally test the versions and digests in `Containerfile`.
2. Merge the change to `main` after CI passes.
3. Create a tag such as `v26.8.2.7-ubi9.8-1`.
4. Push the tag. GitHub Actions builds both architectures, scans the image, publishes it to GHCR, attaches SBOM and provenance attestations, and signs the resulting digest.

Verify a release with GitHub as the keyless identity provider:

```console
cosign verify \
  --certificate-identity-regexp='https://github.com/datopsis/clickhouse-server-ubi9/.github/workflows/release.yml@refs/tags/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

## Operational notes

ClickHouse commonly benefits from `nofile=262144:262144`. Optional capabilities such as `IPC_LOCK`, `NET_ADMIN`, and `SYS_NICE` enable specific advanced behavior, but are deliberately absent from the baseline.

Treat `/var/lib/clickhouse` as durable state, back it up according to your ClickHouse topology, and pin production deployments to an image digest rather than a mutable tag.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and the support policy.

## License

The packaging code in this repository is licensed under Apache License 2.0. ClickHouse and Red Hat UBI remain subject to their respective upstream licenses and terms.
