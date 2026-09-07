# Comparison with the official ClickHouse image

This project is an alternative package of the same upstream ClickHouse release, not a drop-in clone of every official-image behavior. The following snapshot was measured on `linux/amd64` on 2026-09-06 using this repository's local test image and `clickhouse/clickhouse-server:26.8.2.7`.

## Image and runtime

| Area | Datopsis UBI image | Official Ubuntu image |
| --- | --- | --- |
| Base | Red Hat UBI 9 Micro | Ubuntu 22.04 |
| ClickHouse | Official `clickhouse-common-static`, server, and client TGZ content, SHA-512 verified | Official ClickHouse Debian packages |
| Default process user | `101:0` in image metadata; never starts as root | Starts as root by default, prepares/chowns paths, then switches to UID/GID 101; root/custom-ID modes are supported |
| Package manager/download tool | No `dnf`, `microdnf`, `apt`, `curl`, or `wget` | `apt`, `apt-get`, and `wget` remain installed |
| Other notable tools | Bash, coreutils-single, gzip, CA trust, timezone data | Bash, BusyBox links, coreutils, gzip, OpenSSL CLI, CA trust, locales, timezone data, and normal Ubuntu base utilities |
| Installed OS package records | 34 RPM database entries, including 2 signing-key records | 111 Debian packages |
| Local unpacked storage | 845,298,018 bytes (806.1 MiB) | 902,021,165 bytes (860.2 MiB) |
| Filesystem layers | 7 | 11 |
| Built-in health check | Authenticated `SELECT 1` over configured native TCP or native TLS | None in image metadata |
| Read-only root baseline | Supported and smoke-tested | Not the official default; its entrypoint writes configuration and manages ownership |

The UBI image was 56,723,147 bytes (54.1 MiB, about 6.3%) smaller by this local engine's unpacked-size measurement. Registry transfer size, manifest/attestation size, storage-driver sharing, and `arm64` size are different measurements and must be captured from the actual release digest before making published size claims. ClickHouse's static binary dominates both images, so a much smaller base produces a modest total reduction.

## Ports and volumes

Both images declare ports `8123` (HTTP), `9000` (native TCP), and `9009` (inter-server HTTP), and both declare `/var/lib/clickhouse` as a volume. Neither declaration publishes a port or protects it with a firewall. This image logs to the container console and does not require a separate log volume.

Secure ports are configured rather than declared by default: `8443` for HTTPS, `9440` for native TLS, and `9010` for inter-server HTTPS. See [TLS certificates and trust](TLS.md).

## Environment and entrypoint compatibility

| Variable/behavior | Datopsis UBI image | Official image |
| --- | --- | --- |
| `CLICKHOUSE_PASSWORD` / `_FILE` | Yes | Yes |
| `CLICKHOUSE_DB` | Yes; validated as an unquoted identifier | Yes |
| `CLICKHOUSE_USER` | Only `default`; another value fails with guidance | Creates/configures a named user |
| `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT` | No; default user gets access management | Yes |
| `CLICKHOUSE_SKIP_USER_SETUP` | Deliberately no insecure bypass | Yes |
| `CLICKHOUSE_ALWAYS_RUN_INITDB_SCRIPTS` | Yes | Yes |
| `CLICKHOUSE_INIT_TIMEOUT` | Yes; default `60` seconds | Yes; default `1000` retries |
| `CLICKHOUSE_CONFIG` | Yes | Yes |
| `CLICKHOUSE_DATA_DIR` | Yes; default `/var/lib/clickhouse` | Data path is extracted from ClickHouse config |
| `CLICKHOUSE_RUN_AS_ROOT`, UID/GID, no-chown options | No; fixed non-root security model | Yes |
| Init files | Executable/sourced `.sh`, `.sql`, `.sql.gz`, lexical order | Same file types; shell glob order |
| Additional configured disk paths | Operator must provision permissions | Official entrypoint discovers and prepares configured paths |
| Arbitrary OpenShift UID | Smoke-tested with group `0` permissions | Custom `--user` documented upstream; different entrypoint model |

Applications that depend on the official image's named-user creation, root mode, automatic custom-disk ownership, skip-user-setup escape hatch, or exact initialization semantics need an explicit migration plan. Do not add those features automatically: several conflict with this image's non-root and least-privilege goals.

The comparison source is ClickHouse's [official image documentation](https://github.com/ClickHouse/ClickHouse/blob/master/docker/server/README.md), [Ubuntu Dockerfile](https://github.com/ClickHouse/ClickHouse/blob/master/docker/server/Dockerfile.ubuntu), and [entrypoint](https://github.com/ClickHouse/ClickHouse/blob/master/docker/server/entrypoint.sh). Re-measure on every supported release because upstream content and behavior change.
