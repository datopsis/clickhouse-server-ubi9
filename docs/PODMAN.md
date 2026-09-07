# Podman compatibility and version support

Podman is the primary documented local container engine for this Red Hat UBI image. The published OCI image remains portable: GitHub Actions uses Docker Engine and Buildx for native AMD64/ARM64 qualification and multi-architecture release assembly, while user procedures use Podman unless they specifically describe that CI implementation or compare with the official ClickHouse image.

## Supported and tested versions

The first-release support baseline is Podman 5.3 or newer. This is an evidence-based support floor, not a known technical minimum. The complete local smoke suite was run on 2026-09-07 with:

| Component | Version | Platform |
| --- | --- | --- |
| Podman client | 5.3.2 | Windows AMD64 |
| Podman server | 5.3.1 | Linux AMD64 in Podman Machine |

Run `podman version` and record both client and server versions when using a remote client. The server version and architecture execute the container; the client values alone are not runtime qualification evidence. Native Linux AMD64 and ARM64 image behavior is separately qualified in GitHub Actions, currently using Docker Engine. A future Podman version or architecture result should be added here only after the complete smoke suite passes.

## Build and smoke test

Podman's default build format is OCI. Use Docker manifest format for local builds because the OCI image configuration does not preserve the Containerfile `HEALTHCHECK` metadata used by the smoke suite:

```console
podman build --format docker --file Containerfile \
  --tag ghcr.io/datopsis/clickhouse-server-ubi9:test .
CONTAINER_RUNTIME=podman \
  IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9:test \
  bash tests/smoke.sh
```

Images pulled from the project's release registry already contain the release workflow's image metadata; `--format docker` is a local build instruction, not a `podman pull` requirement.

## Rootless operation and storage

Prefer rootless Podman and a named volume for the basic case. Named volumes avoid host user-namespace ownership calculations:

```console
podman volume create clickhouse-data
podman run --detach --name clickhouse \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume clickhouse-data:/var/lib/clickhouse \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

For a Linux bind mount, use `podman unshare chown 101:0 <path>` to express the image identity through the rootless user namespace. Do not assume that container UID `101` must appear as host UID `101`. Podman's `:U` volume option is an alternative, but it recursively changes the host tree and can be slow. Follow [rootless storage and permissions](ROOTLESS.md) for complete named-volume, bind-mount, SELinux, additional-disk, and OpenShift procedures.

On macOS and Windows, Podman normally uses a remote Linux virtual machine. Bind-mount source paths are resolved and made available through that environment, and their ownership behavior differs from a native Linux host. Prefer a named volume for quick starts and perform production storage qualification on the target Linux or OpenShift storage implementation.

## Compose

`podman compose` is a wrapper around an external Compose provider. Install either `podman-compose` or another compatible provider, confirm the selected provider with `podman compose version`, change the example password in `compose.yaml`, and then run:

```console
podman compose up --detach
podman compose ps
podman compose down
```

Removing the Compose application does not replace an intentional backup or retention decision for the named data volume.

Authoritative references:

- [Podman build formats](https://docs.podman.io/en/stable/markdown/podman-build.1.html)
- [Podman run volume ownership and user namespaces](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
- [Podman Compose providers](https://docs.podman.io/en/latest/markdown/podman-compose.1.html)
